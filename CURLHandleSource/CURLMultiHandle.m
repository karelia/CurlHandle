//
//  CURLMultiHandle.m
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


#import "CURLMultiHandle.h"

#import "CURLTransfer+MultiSupport.h"
#import "CURLSocketRegistration.h"


@interface CURLMultiHandle()

#pragma mark - Private Properties

@property (readonly, copy, nonatomic) NSArray* transfers;
@property (strong, nonatomic) NSMutableArray* sockets;
@property (assign, nonatomic) dispatch_queue_t queue;
@property (assign, nonatomic) dispatch_source_t timer;

@end


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


@implementation CURLMultiHandle

#pragma mark - Synthesized Properties

@synthesize sockets = _sockets;
@synthesize queue = _queue;

#pragma mark - Object Lifecycle

+ (CURLMultiHandle*)sharedInstance;
{
    static CURLMultiHandle* instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CURLMultiHandle alloc] init];
        [instance startup];
    });

    return instance;
}

- (id)init
{
    if ((self = [super init]) != nil)
    {
        if ([self createTimer])
        {
            _transfers = [[NSMutableArray alloc] init];
            self.sockets = [NSMutableArray array];
#if COUNT_INSTANCES
            ++gInstanceCount;
#endif
        }
        else
        {
            [self release];
            self = nil;
        }
    }

    return self;
}

- (void)dealloc
{
    CURLMultiLog(@"deallocing");
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

- (void)startup

{
    CURLMultiLog(@"started");
}


- (void)shutdown
{
    // if the queue is gone, we've already been shut down and are probably being disposed
    dispatch_source_t timer = self.timer;
    if (timer)
    {
        CURLMultiLog(@"shutdown");
        self.timer = nil;
        dispatch_source_cancel(timer);
    }
    else
    {
        CURLMultiLogError(@"shutdown called multiple times");
    }
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
            
            // http://curl.haxx.se/libcurl/c/curl_multi_socket_action.html suggests you typically fire a timeout to get it started
            int runningHandles;
            curl_multi_socket_action(_multi, CURL_SOCKET_TIMEOUT, 0, &runningHandles);
        }
        else
        {
            CURLMultiLogError(@"failed to add transfer %@", transfer);
            [transfer completeWithCode:result isMulti:YES];
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
    CURLMcode result = CURLM_OK;
    _multi = curl_multi_init();
    if (_multi)
    {
        result = curl_multi_setopt(_multi, CURLMOPT_TIMERFUNCTION, timeout_callback);
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
}

- (void)cleanupMulti;
{
    CURLMultiLog(@"cleaning up");

    for (CURLTransfer *aTransfer in self.transfers)
    {
        [self suspendTransfer:aTransfer];
    }

    // give handles a last chance to process
    // I'm not sure this is strictly the right thing to do, since timeout hasn't actually been reached. Mike
    [self processMulti:_multi action:0 forSocket:CURL_SOCKET_TIMEOUT];;

    [_transfers release]; _transfers = nil;
    self.sockets = nil;

    CURLMcode result = curl_multi_cleanup(_multi);
    NSAssert(result == CURLM_OK, @"cleaning up multi failed unexpectedly with error %d", result);
}

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
            CURLMsg* message;
            int count;
            while ((message = curl_multi_info_read(multi, &count)) != NULL)
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
                        [transfer completeWithCode:code isMulti:NO];

                        // ...then tell it that it's no longer in use by the multi, which breaks the reference cycle between us
                        //[transfer removedByMulti:self];

                        [transfer autorelease];
                    }
                    else
                    {
                        // this really shouldn't happen - there should always be a matching CURLTransfer - but just in case...
                        CURLMultiLogError(@"SOMETHING WRONG: done msg result %d for easy without a matching CURLTransfer %p", code, easy);
                        result = curl_multi_remove_handle(multi, message->easy_handle);
                        NSAssert(result == CURLM_OK, @"failed to remove curl easy from curl multi - something odd going on here");
                    }
                }
                else
                {
                    CURLMultiLogError(@"got unexpected multi message %d", message->msg);
                }
            }
        }
        else
        {
            CURLMultiLogError(@"curl_multi_socket_action returned error %d", result);
        }
    }

    CURLMultiLogDetail(@"\nDONE processing for socket %d action %@\n\n", socket, kActionNames[action]);
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

- (BOOL)createTimer
{
    [self multiCreate];
    
    if (_multi)
    {
        dispatch_queue_t queue = [self createQueue];
        if (queue)
        {
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
            _timerIsSuspended = YES;
            // CURLM will command us to resume the timer when it's ready

            dispatch_source_set_event_handler(timer, ^{
                CURLMultiLog(@"timer fired");

                // perform processing
                [self processMulti:_multi action:0 forSocket:CURL_SOCKET_TIMEOUT];
            });

            dispatch_source_set_cancel_handler(timer, ^{

                NSAssert(self.timer == nil, @"timer property should have been cleared by now");

                [self cleanupMulti];

                dispatch_queue_t queue = self.queue;
                dispatch_async(dispatch_get_main_queue(), ^{
                    dispatch_release(timer);
                    dispatch_release(queue);
                    CURLMultiLog(@"released queue and timer");
                });

                self.queue = nil;
            });

            self.timer = timer;
            self.queue = queue;
        }
    }

    return _multi && self.timer && self.queue;
}

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
    CURLMultiHandle* source = userp;
    [source setTimeout:timeout_ms];

    return CURLM_OK;
}

int socket_callback(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp)
{
    CURLMultiHandle* multi = userp;
    NSCAssert([multi transferForHandle:easy] != nil, @"socket callback for a handle %p that isn't managed by %@", easy, multi);

    [multi updateRegistration:socketp forSocket:s to:what];
    
    return CURLM_OK;
}


@end
