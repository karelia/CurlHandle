//
//  CURLHandle
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

/**
 As mentioned in the header, the intention is that all access to the multi
 is controlled via our internal serial queue. The queue also protects additions to
 and removals from our array of the transfers that we're managing.

 The CURL multi handle is generally not stored by the CURLMUlti object. 
 Instead it is set up when the dispatch timer is created, and it's value is
 captured by the timer block, which passes it on to everything else that needs it.
 
 The one (annoying) exception to this is that the socket_callback from curl
 only has one context value, which we use to pass a pointer to the CURLMulti
 object. Since the code called by this callback needs access to the multi value,
 we have to store it on CURLMulti - using the multiForSocket property.
 
 However, these callbacks only occur as a result of calling curl_multi_socket_action(),
 which only happens from within the processMulti: call. Therefore, we only set
 multiForSocket at the start of the processMulti call, and we clear it again at the end.

 The other GCD structures (self.timer and self.queue) should stay valid until they are destroyed
 as part of the shutdown process. 
 
 # Shutdown
 
 Shutdown just cancels the timer, and removes our reference to it. All other cleanup happens
 in the timer's cancel handler. This removes all easy handles from the multi, cleans it up, and
 disposes of it. It then releases the queue.
 
 Because the timer and the queue blocks both contain references to self, the object itself
 should not get deallocated until both the timer and queue have gone away. 
 
 Since the timer block is the only thing that actually causes activity on the multi, 
 once the timer has been cancelled, nothing else should actually touch the multi,
 other than the cleanup block.

 The queue itself is cleaned up on the main queue, once the rest of the shutdown process has finished.
 This additional paranoia (using the main queue for the cleanup) is probably not strictly necessary any more.
 */


#import "CURLTransferStack.h"

#import "CURLTransfer+MultiSupport.h"
#import "CURLSocketRegistration.h"


@interface CURLTransferStack()

#pragma mark - Private Properties

@property (readonly, copy, nonatomic) NSArray* transfers;
@property (strong, nonatomic) NSMutableArray* sockets;
@property (readonly, nonatomic) dispatch_source_t timer;

@end


#define USE_MULTI_SOCKET 0              // buggy for now in my testing
#define USE_GLOBAL_QUEUE YES            // turn this on to share one queue across all instances
#define COUNT_INSTANCES NO              // turn this on for a bit of debugging to ensure that things are getting cleaned up properly

#if COUNT_INSTANCES
static NSInteger gInstanceCount = 0;
#endif

NSString *const kActionNames[] =
{
    @"CURL_SOCKET_TIMEOUT",
    @"CURL_CSELECT_IN",
    @"CURL_CSELECT_OUT",
    @"",
    @"CURL_CSELECT_ERR",
};

#pragma mark - Callback Prototypes

static int timeout_callback(CURLM *multi, long timeout_ms, void *userp);
static int socket_callback(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp);


@implementation CURLTransferStack

#pragma mark - Synthesized Properties

@synthesize sockets = _sockets;
@synthesize queue = _queue;

#pragma mark - Object Lifecycle

+ (CURLTransferStack*)sharedInstance;
{
    static CURLTransferStack* instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CURLTransferStack alloc] init];
    });

    return instance;
}

- (id)init
{
    if (self = [super init])
    {
        // Setup multi handle
        [self multiCreate];
        if (!_multi)
        {
            [self release]; return nil;
        }
        
        
        // Setup queue
        _queue = [self createQueue];
        if (!_queue)
        {
            [self release]; return nil;
        }
        
        
#if USE_MULTI_SOCKET
        // Create timer
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
        if (!_timer)
        {
            [self release]; return nil;
        }
        
        _timerIsSuspended = YES;
        // CURLM will command us to resume the timer when it's ready
        
        dispatch_source_set_event_handler(_timer, ^{
            CURLMultiLog(@"timer fired");
            
            // perform processing
            [self processMulti:_multi action:0 forSocket:CURL_SOCKET_TIMEOUT];
        });
        
        dispatch_source_set_cancel_handler(_timer, ^{
            
            NSAssert(self.timer == nil, @"timer property should have been cleared by now");
            
            [self cleanupMulti];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                dispatch_release(_timer); _timer = NULL;
                dispatch_release(_queue); _queue = NULL;
                CURLMultiLog(@"released queue and timer");
            });
        });
        
#endif
        
        
        // Setup other ivars
        _transfers = [[NSMutableArray alloc] init];
        self.sockets = [NSMutableArray array];
#if COUNT_INSTANCES
        ++gInstanceCount;
#endif
        
        CURLMultiLog(@"started");
    }
    
    return self;
}

- (void)dealloc
{
    CURLMultiLog(@"deallocing");
    [self cleanupMulti];
    
    if (_queue)
    {
        dispatch_release(_queue); _queue = NULL;
    }
    
    NSAssert((_multi == NULL) && (_timer == NULL) && (_queue == NULL), @"should have been shut down by the time we're dealloced");

    [_transfers release];
    [_sockets release];

#if COUNT_INSTANCES
    --gInstanceCount;
    CURLMultiLog(@"dealloced: %ld instances remaining", gInstanceCount);
#else
    CURLMultiLog(@"dealloced");
#endif
    
    [super dealloc];
}

#pragma mark - Startup / Shutdown

- (void)shutdown
{
#if USE_MULTI_SOCKET
    // if the queue is gone, we've already been shut down and are probably being disposed
    dispatch_source_t timer = self.timer;
    if (timer)
    {
        CURLMultiLog(@"shutdown");
        _timer = NULL;  // released later
        dispatch_source_cancel(timer);
    }
    else
    {
        CURLMultiLogError(@"shutdown called multiple times");
    }
#endif
}

#pragma mark - Transfer Management

- (NSArray *)transfers; { return [[_transfers copy] autorelease]; }

- (void)beginTransfer:(CURLTransfer *)transfer;
{
    NSAssert(self.queue, @"need queue");
    
    dispatch_async(self.queue, ^{
        
        NSAssert(![self.transfers containsObject:transfer], @"shouldn't add a transfer twice");
        
        CURLMultiLog(@"adding transfer %@", transfer);
        
        CURLMcode result = curl_multi_add_handle(_multi, [transfer curlHandle]);
        if (result == CURLM_OK)
        {
            [_transfers addObject:transfer];
            
#if USE_MULTI_SOCKET
            // http://curl.haxx.se/libcurl/c/curl_multi_socket_action.html suggests you typically fire a timeout to get it started
            [self processMulti:_multi action:CURL_SOCKET_TIMEOUT forSocket:0];
#else
            // Start up the queue again if needed
            if (!_isRunningProcessingLoop)
            {
                _isRunningProcessingLoop = [self runProcessingLoop];
            }
#endif
        }
        else
        {
            CURLMultiLogError(@"failed to add transfer %@", transfer);
            NSAssert(result != CURLM_CALL_MULTI_SOCKET, @"CURLM_CALL_MULTI_SOCKET doesn't make sense as a transfer failure code");
            [transfer completeWithError:[NSError errorWithDomain:CURLMcodeErrorDomain code:result userInfo:nil]];
        }
    });
}

- (void)suspendTransfer:(CURLTransfer *)transfer;
{
    NSAssert([_transfers containsObject:transfer], @"we should be managing this transfer");
    
    CURLMultiLog(@"removed transfer %@", transfer);
    CURLMcode result = curl_multi_remove_handle(_multi, [transfer curlHandle]);
    
    NSAssert(result == CURLM_OK, @"failed to remove curl easy from curl multi - something odd going on here");
    [_transfers removeObject:transfer];
}

- (CURLTransfer*)transferForHandle:(CURL*)easy
{
    CURLTransfer* result = nil;
    CURLTransfer* info;
    CURLcode code = curl_easy_getinfo(easy, CURLINFO_PRIVATE, &info);
    if (code == CURLE_OK)
    {
        NSAssert([info isKindOfClass:[CURLTransfer class]], @"easy handle doesn't seem to be backed by a CURLTransfer object");

        result = info;
    }
    else
    {
        NSAssert(NO, @"failed to get backing object for easy handle");
    }

    return result;
}

#pragma mark - Multi Handle Management

- (void)multiCreate;
{
    _multi = curl_multi_init();
    
#if USE_MULTI_SOCKET
    if (_multi)
    {
        CURLMcode result = curl_multi_setopt(_multi, CURLMOPT_TIMERFUNCTION, timeout_callback);
        
        if (result == CURLM_OK)
        {
            result = curl_multi_setopt(_multi, CURLMOPT_TIMERDATA, self);
        }

        if (result == CURLM_OK)
        {
            result = curl_multi_setopt(_multi, CURLMOPT_SOCKETFUNCTION, socket_callback);
        }

        if (result == CURLM_OK)
        {
            result = curl_multi_setopt(_multi, CURLMOPT_SOCKETDATA, self);
        }

        if (result != CURLM_OK)
        {
            curl_multi_cleanup(_multi);
            _multi = nil;
        }
    }
#endif
}

- (void)cleanupMulti;
{
    CURLMultiLog(@"cleaning up");

    dispatch_sync(_queue, ^{    // might as well serialise access
        
    for (CURLTransfer *aTransfer in self.transfers)
    {
        [self suspendTransfer:aTransfer];
    }

#if USE_MULTI_SOCKET
    // give handles a last chance to process
    // I'm not sure this is strictly the right thing to do, since timeout hasn't actually been reached. Mike
    [self processMulti:_multi action:0 forSocket:CURL_SOCKET_TIMEOUT];;
#endif

    [_transfers release]; _transfers = nil;
    self.sockets = nil;

    if (!_multi) return;
    CURLMcode result = curl_multi_cleanup(_multi);
    NSAssert(result == CURLM_OK, @"cleaning up multi failed unexpectedly with error %d", result);
    _multi = NULL;
        
    });
}

#if USE_MULTI_SOCKET

- (void)processMulti:(CURLM*)multi action:(int)action forSocket:(int)socket
{
    //BOOL isTimeout = socket == CURL_SOCKET_TIMEOUT;
    
    // process the multi
    //if (!isTimeout)
    {
        int running;
        CURLMultiLogDetail(@"\n\nSTART processing for socket %d action %@", socket, kActionNames[action]);
        
        CURLMcode result;
        do
        {
            result = curl_multi_socket_action(_multi, socket, action, &running);
        }
        while (result == CURLM_CALL_MULTI_SOCKET);
        
        if (result == CURLM_OK)
        {
            CURLMultiLogDetail(@"%d handles reported as running", running);
            [self processTransferMessages];
        }
        else
        {
            CURLMultiLogError(@"curl_multi_socket_action returned error %d", result);
        }
    }
    
    CURLMultiLogDetail(@"\nDONE processing for socket %d action %@\n\n", socket, kActionNames[action]);
}

#else

- (BOOL)runProcessingLoop;
{
    CURLMcode result;
    int runningHandles;
    do
    {
        result = curl_multi_perform(_multi, &runningHandles);
    }
    while (result == CURLM_CALL_MULTI_PERFORM);
    
    if (result != CURLM_OK)
    {
        // If something went wrong, I guess there's not a lot we can do about it. After all, this is
        // an error in the overall management of transfers, not one particular easy handle. Might as
        // well try to soldier on after logging about it; you never know it might work, or we'll
        // crash or something!
        CURLMultiLogError(@"curl_multi_wait() returned %i", result);
    }
    
    
    // Once there are fewer running handles than we are tracking, some should have finished
    if (runningHandles < self.transfers.count)
    {
        [self processTransferMessages];
        
        // Bail out once we've run out of handles/transfers, as there's no point burning CPU to
        // service an empty multi handle. Will be rescheduled when the next transfer starts
        if (runningHandles == 0)
        {
            NSAssert(self.transfers.count == 0, @"No handles running, but still CURLTransfers being tracked");
            return NO;
        }
    }
    
    NSAssert(self.transfers.count, @"Servicing a multi handle without any CURLTransfers");
    NSAssert(runningHandles > 0, @"There are still running handles, but apparently still CURLTransfers being tracked");
    
    
    // Wait for something to happen
    result = curl_multi_wait(_multi,
                             NULL, NULL,    // no extra file descriptors to track
                             500,   // stops new transfers waiting too long to start
                             NULL); // don't care about number of handles here
    if (result != CURLM_OK)
    {
        // If something went wrong in waiting, I guess there's not a lot we can do about it. Might
        // as well carry on processing the handle and use up more CPU, but log about it
        CURLMultiLogError(@"curl_multi_wait() returned %i", result);
    }
    
    
    // Reschedule such that new transfers can make it into the queue
    dispatch_async(self.queue, ^{
        // Catch and report exceptions since GCD will just crash on us
        @try
        {
            // If all in-process transfers have been cancelled, we'll arrive at this point with no
            // transfers registered with us, and no handles registered with the multi handle either.
            // Thus it's time to stop processing until a new transfer starts
            _isRunningProcessingLoop = (self.transfers.count ? [self runProcessingLoop] : NO);
        }
        @catch (NSException *exception) {
            [[NSClassFromString(@"NSApplication") sharedApplication] reportException:exception];
        }
    });
    
    return YES;
}

#endif

- (void)processTransferMessages
{
    CURLMsg* message;
    int count;
    while ((message = curl_multi_info_read(_multi, &count)) != NULL)
    {
        CURLMultiLog(@"got message (%d remaining)", count);
        if (message->msg == CURLMSG_DONE)
        {
            CURLcode code = message->data.result;
            CURL* easy = message->easy_handle;
            CURLTransfer* transfer = [self transferForHandle:easy];
            if (transfer)
            {
                const char* url;
                curl_easy_getinfo(easy, CURLINFO_EFFECTIVE_URL, &url);
                CURLMultiLog(@"done msg result %d for %@ %s", code, transfer, url);
                [transfer retain];
                
                // the order is important here - we remove the transfer from the multi first...
                [self suspendTransfer:transfer];
                
                // ...then tell the easy transfer to complete, which can cause curl_easy_cleanup to be called
                [transfer completeWithCode:code];
                
                // ...then tell it that it's no longer in use by the multi, which breaks the reference cycle between us
                //[transfer removedByMulti:self];
                
                [transfer autorelease];
            }
            else
            {
                // this really shouldn't happen - there should always be a matching CURLTransfer - but just in case...
                CURLMultiLogError(@"SOMETHING WRONG: done msg result %d for easy without a matching CURLTransfer %p", code, easy);
                CURLMcode result = curl_multi_remove_handle(_multi, message->easy_handle);
                NSAssert(result == CURLM_OK, @"failed to remove curl easy from curl multi - something odd going on here");
            }
        }
        else
        {
            CURLMultiLogError(@"got unexpected multi message %d", message->msg);
        }
    }
}

- (void)updateRegistration:(CURLSocketRegistration *)registration forSocket:(curl_socket_t)socket to:(int)what
{
    NSAssert(_multi != nil, @"should never be called without a multi value");
    {
        if (what == CURL_POLL_NONE)
        {
            NSAssert(registration == nil, @"should have no socket object first time");
        }

        if (!registration)
        {
            NSAssert(what != CURL_POLL_REMOVE, @"shouldn't need to make a socket if we're being asked to remove it");
            registration = [[CURLSocketRegistration alloc] init];
            [self.sockets addObject:registration];
            curl_multi_assign(_multi, socket, registration);
            CURLMultiLog(@"new socket:%@", registration);
            [registration release];
        }

        [registration updateSourcesForSocket:socket mode:what multi:self];
        CURLMultiLog(@"updated socket:%@", registration);

        if (what == CURL_POLL_REMOVE)
        {
            NSAssert(registration != nil, @"should have socket");
            CURLMultiLog(@"removed socket:%@", registration);
            [self.sockets removeObject:registration];
            curl_multi_assign(_multi, socket, nil);
        }
    }
}

#pragma mark - Queue Management

- (dispatch_queue_t)createQueue
{
    dispatch_queue_t queue;

#if USE_GLOBAL_QUEUE

    // make a single queue, stored in a static, which we use for all CURLMulti instances
    static dispatch_queue_t sGlobalQueue;
    static dispatch_once_t sGlobalQueueToken;
    dispatch_once(&sGlobalQueueToken, ^{
        sGlobalQueue = dispatch_queue_create("com.karelia.CURLMulti", NULL);
    });

    queue = sGlobalQueue;
    dispatch_retain(queue);
#else

    // make a new queue for each CURLMulti instance
    NSString* name = [NSString stringWithFormat:@"com.karelia.CURLMulti.%p", self];
    queue = dispatch_queue_create([name UTF8String], NULL);

#endif

    CURLMultiLog(@"created queue");
    return queue;
}


#pragma mark - Timer Management

@synthesize timer = _timer;

- (void)setTimeout:(long)timeout_ms
{
    // if multi is nil, the object is being thrown away
    if ([self notShutdown])
    {
        dispatch_source_t timer = self.timer;
        NSAssert(timer != nil, @"should still have a timer");

        CURLMultiLog(@"timeout changed to %ldms", (long)timeout_ms);
        
        if (timer)
        {
            if (timeout_ms < 0)
            {
                if (!_timerIsSuspended)
                {
                    _timerIsSuspended = YES;
                    dispatch_suspend(timer);
                }
            }
            else
            {
                int64_t timeout_ns = timeout_ms * NSEC_PER_MSEC;
                
                dispatch_source_set_timer(timer,
                                          dispatch_time(DISPATCH_TIME_NOW, timeout_ns), // fire when timeout is reached
                                          DISPATCH_TIME_FOREVER,                        // libcurl takes care of rescheduling
                                          timeout_ns/100);                              // we're fairly delay tolerant
                
                if (_timerIsSuspended)
                {
                    _timerIsSuspended = NO;
                    dispatch_resume(timer);
                }
            }
        }
    }
}

#pragma mark - Callback Support

- (NSString*)nameForType:(dispatch_source_type_t)type
{
    return (type == DISPATCH_SOURCE_TYPE_READ) ? @"reader" : @"writer";
}

- (dispatch_source_t)updateSource:(dispatch_source_t)source type:(dispatch_source_type_t)type socket:(int)socket registration:(CURLSocketRegistration *)registration required:(BOOL)required
{
#if USE_MULTI_SOCKET
    if (required)
    {
        if (!source)
        {
            CURLMultiLog(@"added %@ dispatch source for socket %d", [self nameForType:type], socket);
            source = dispatch_source_create(type, socket, 0, self.queue);

            NSAssert(_multi != nil, @"should never be called without a multi value");
            int action = (type == DISPATCH_SOURCE_TYPE_READ) ? CURL_CSELECT_IN : CURL_CSELECT_OUT;
            dispatch_source_set_event_handler(source, ^{
                CURLMultiLog(@"%@ dispatch source fired for socket %d with value %ld", [self nameForType:type], socket, dispatch_source_get_data(source));
                BOOL sourceIsActive = [self.sockets containsObject:registration] && [registration ownsSource:source];
                NSAssert(sourceIsActive, @"should have active source");
                if (sourceIsActive)
                {
                    [self processMulti:_multi action:action forSocket:socket];
                }
            });

            dispatch_source_set_cancel_handler(source, ^{
                CURLMultiLog(@"removed %@ dispatch source for socket %d", [self nameForType:type], socket);
                dispatch_release(source);
            });

            dispatch_resume(source);
        }
    }
    else if (source)
    {
        CURLMultiLog(@"removing %@ dispatch source for socket %d", [self nameForType:type], socket);
        dispatch_source_cancel(source);
        source = nil;
    }
#endif

    return source;
}


#pragma mark - Utilities

- (BOOL)notShutdown
{
    return self.timer != nil;
}

- (NSString*)description
{
    NSString* managing = [self.transfers count] ? [NSString stringWithFormat:@": %@", [self.transfers componentsJoinedByString:@","]] : @": no transfers";
    return [NSString stringWithFormat:@"<MULTI %p%@>", self, managing];
}

#pragma mark - Callbacks


int timeout_callback(CURLM *multi, long timeout_ms, void *userp)
{
    CURLTransferStack* source = userp;
    [source setTimeout:timeout_ms];

    return CURLM_OK;
}

int socket_callback(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp)
{
    CURLTransferStack* multi = userp;
    NSCAssert([multi transferForHandle:easy] != nil, @"socket callback for a handle %p that isn't managed by %@", easy, multi);

    [multi updateRegistration:socketp forSocket:s to:what];
    
    return CURLM_OK;
}


@end
