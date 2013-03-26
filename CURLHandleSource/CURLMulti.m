//
//  CURLMulti.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

/**
 As mentioned in the header, the intention is that all access to the multi
 is controlled via our internal serial queue. The queue also protects additions to
 and removals from our array of the easy handles that we're managing.

 The CURL multi handle is stored in the property self.multi, which is atomic.
 This value is set to nil when we're shutting down.

 The only methods that access the multi should all start with the word multi.

 In each case they access it via the checkMulti method, which includes an assertion to check
 that it's being called from the our internal queue.

 The other GCD structures (self.timer and self.queue) should stay valid until they are destroyed
 as part of the shutdown process. Anything that uses them checks their validity first by calling
 [self notShutdown], which actually just checks the value of self.multi. If this returns NO, it indicates
 that the shutdown is in progress (or completed). The queue and timer aren't safe to use after this
 as they will be destroyed at some point. 
 
 The timer is cleaned up on the queue.
 
 The queue itself is cleaned up on the main queue, once the rest of the shutdown process has finished.
 */


#import "CURLMulti.h"

#import "CURLHandle.h"
#import "CURLSocket.h"

@interface CURLMulti()

#pragma mark - Private Properties

@property (strong, nonatomic) NSMutableArray* pendingAdditions;
@property (strong, nonatomic) NSMutableArray* pendingRemovals;
@property (strong, nonatomic) NSMutableArray* handles;
@property (assign, atomic) CURLM* multiForSocket;
@property (assign, nonatomic) dispatch_queue_t queue;
@property (assign, nonatomic) dispatch_source_t timer;

- (void)updateTimeout:(NSInteger)timeout;
- (void)multiUpdateSocket:(CURLSocket*)socket raw:(curl_socket_t)raw what:(NSInteger)what;

@end

static int kMaximumTimeoutMilliseconds = 1000;

#define USE_GLOBAL_QUEUE 1

NSString *const kActionNames[] =
{
    @"CURL_SOCKET_TIMEOUT",
    @"",
    @"CURL_CSELECT_IN",
    @"CURL_CSELECT_OUT",
    @"",
};

#pragma mark - Callback Prototypes

static int timeout_callback(CURLM *multi, long timeout_ms, void *userp);
static int socket_callback(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp);


@implementation CURLMulti

#pragma mark - Synthesized Properties

@synthesize handles = _handles;
@synthesize pendingAdditions = _pendingAdditions;
@synthesize pendingRemovals = _pendingRemovals;
@synthesize queue = _queue;
@synthesize timer = _timer;
@synthesize multiForSocket = _multiForSocket;

#pragma mark - Object Lifecycle

+ (CURLMulti*)sharedInstance;
{
    static CURLMulti* instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CURLMulti alloc] init];
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
            self.handles = [NSMutableArray array];
            self.pendingAdditions = [NSMutableArray array];
            self.pendingRemovals = [NSMutableArray array];
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
    NSAssert((_multiForSocket == nil) && (_timer == nil) && (_queue == nil), @"should have been shut down by the time we're dealloced");

    [_handles release];
    [_pendingRemovals release];
    [_pendingAdditions release];
    
    CURLMultiLog(@"dealloced");
    [super dealloc];
}

#pragma mark - Startup / Shutdown

- (void)startup

{
    CURLMultiLog(@"started monitoring");
    dispatch_resume(self.timer);
}


- (void)shutdown
{
    // if the queue is gone, we've already been shut down and are probably being disposed
    dispatch_source_t timer = self.timer;
    if (timer)
    {
        CURLMultiLog(@"shutdown");
        dispatch_source_cancel(timer);
        self.timer = nil;
    }
    else
    {
        CURLMultiLog(@"shutdown called multiple times");
    }
}

#pragma mark - Easy Handle Management

- (void)manageHandle:(CURLHandle*)handle
{
    NSAssert(self.queue, @"need queue");
    NSAssert(self.pendingAdditions, @"need additions array");

    dispatch_async(self.queue, ^{
        if ([self.pendingRemovals containsObject:handle])
        {
            [self.pendingRemovals removeObject:handle];
        }
        else
        {
            [self.pendingAdditions addObject:handle];
        }
    });
}

- (void)stopManagingHandle:(CURLHandle*)handle
{
    NSAssert(self.queue, @"need queue");
    NSAssert(self.pendingRemovals, @"need removals array");

    dispatch_async(self.queue, ^{
        if ([self.pendingAdditions containsObject:handle])
        {
            [self.pendingAdditions removeObject:handle];
        }
        else
        {
            [self.pendingRemovals addObject:handle];
        }
    });
}

- (CURLHandle*)findHandleWithEasyHandle:(CURL*)easy
{
    CURLHandle* result = nil;
    CURLHandle* info;
    CURLcode code = curl_easy_getinfo(easy, CURLINFO_PRIVATE, &info);
    if (code == CURLE_OK)
    {
        NSAssert([info isKindOfClass:[CURLHandle class]], @"easy handle doesn't seem to be backed by a CURLHandle object");

        result = info;
    }
    else
    {
        NSAssert(NO, @"failed to get backing object for easy handle");
    }

    return result;
}

#pragma mark - Multi Handle Management

- (CURLM*)multiCreate
{
    CURLMcode result = CURLM_OK;
    CURLM* multi = curl_multi_init();
    if (multi)
    {
        result = curl_multi_setopt(multi, CURLMOPT_TIMERFUNCTION, timeout_callback);
        if (result == CURLM_OK)
        {
            result = curl_multi_setopt(multi, CURLMOPT_TIMERDATA, self);
        }

        if (result == CURLM_OK)
        {
            result = curl_multi_setopt(multi, CURLMOPT_SOCKETFUNCTION, socket_callback);
        }

        if (result == CURLM_OK)
        {
            result = curl_multi_setopt(multi, CURLMOPT_SOCKETDATA, self);
        }

        if (result != CURLM_OK)
        {
            curl_multi_cleanup(multi);
            multi = nil;
        }
    }

    return multi;
}

- (void)cleanupMulti:(CURLM*)multi
{
    [self.pendingAdditions removeAllObjects];
    [self.pendingRemovals removeAllObjects];
    [self.pendingRemovals addObjectsFromArray:self.handles];

    // give handles a last chance to process
    [self processMulti:multi action:0 forSocket:CURL_SOCKET_TIMEOUT];

    self.handles = nil;
    self.pendingRemovals = nil;
    self.pendingAdditions = nil;

    CURLMcode result = curl_multi_cleanup(multi);
    NSAssert(result == CURLM_OK, @"cleaning up multi failed unexpectedly with error %d", result);
}

- (void)processMulti:(CURLM*)multi action:(int)action forSocket:(int)socket
{
    [self performAdditionsWithMulti:multi];

    // process the multi
    int running;
    CURLMultiLog(@"\n\nSTART processing for socket %d action %@", socket, kActionNames[action+1]);
    CURLMcode result;
    do
    {
        self.multiForSocket = multi;
        result = curl_multi_socket_action(multi, socket, action, &running);
        self.multiForSocket = nil;
    } while (result == CURLM_CALL_MULTI_SOCKET);
    
    if (result == CURLM_OK)
    {
        CURLMultiLog(@"%d handles reported as running", running);
        CURLMsg* message;
        int count;
        while ((message = curl_multi_info_read(multi, &count)) != NULL)
        {
            CURLMultiLog(@"got message (%d remaining)", count);
            if (message->msg == CURLMSG_DONE)
            {
                CURLcode code = message->data.result;
                CURL* easy = message->easy_handle;
                CURLHandle* handle = [self findHandleWithEasyHandle:easy];
                if (handle)
                {
                    CURLMultiLog(@"done msg result %d for %@", code, handle);
                    [self multi:multi removeHandle:handle];
                    [self.pendingRemovals removeObject:handle]; // just in case it was already scheduled for removal
                    [handle completeWithCode:code];
                    [handle removedByMulti:self];
                }
                else
                {
                    // this really shouldn't happen - there should always be a matching CURLHandle - but just in case...
                    CURLMultiLog(@"SOMETHING WRONG: done msg result %d for easy without a matching CURLHandle %p", code, easy);
                    result = curl_multi_remove_handle(multi, message->easy_handle);
                    NSAssert(result == CURLM_OK, @"failed to remove curl easy from curl multi - something odd going on here");
                }
            }
            else
            {
                CURLMultiLog(@"got unexpected multi message %d", message->msg);
            }
        }
    }
    else
    {
        CURLMultiLog(@"curl_multi_socket_action returned error %d", result);
    }

    [self performRemovalsWithMulti:multi];

    CURLMultiLog(@"\nDONE processing for socket %d action %@\n\n", socket, kActionNames[action+1]);
}

- (void)performAdditionsWithMulti:(CURLM*)multi
{
    // process the pending additions
    for (CURLHandle* handle in self.pendingAdditions)
    {
        NSAssert(![self.handles containsObject:handle], @"shouldn't add a handle twice");
        CURLMcode result = curl_multi_add_handle(multi, [handle curl]);
        if (result == CURLM_OK)
        {
            CURLMultiLog(@"added handle %@", handle);
            [self.handles addObject:handle];
        }
        else
        {
            CURLMultiLog(@"failed to add handle %@", handle);
            [handle completeWithMultiCode:result];
        }
    }
    
    [self.pendingAdditions removeAllObjects];
}

- (void)performRemovalsWithMulti:(CURLM*)multi
{
    // process the pending removals
    for (CURLHandle* handle in self.pendingRemovals)
    {
        NSAssert([self.handles containsObject:handle], @"we should be managing this handle");
        [self multi:multi removeHandle:handle];
        [handle removedByMulti:self];
    }
    [self.pendingRemovals removeAllObjects];
}

- (void)multi:(CURLM*)multi removeHandle:(CURLHandle*)handle
{
    CURLMultiLog(@"removed handle %@", handle);
    CURLMcode result = curl_multi_remove_handle(multi, [handle curl]);
    NSAssert(result == CURLM_OK, @"failed to remove curl easy from curl multi - something odd going on here");
    [self.handles removeObject:handle];
}

- (void)multiUpdateSocket:(CURLSocket*)socket raw:(curl_socket_t)raw what:(NSInteger)what
{
    CURLM* multi = self.multiForSocket;
    if (multi)
    {
        if (what == CURL_POLL_NONE)
        {
            NSAssert(socket == nil, @"should have no socket object first time");
        }

        if (!socket)
        {
            NSAssert(what != CURL_POLL_REMOVE, @"shouldn't need to make a socket if we're being asked to remove it");
#ifndef __clang_analyzer__
            socket = [[CURLSocket alloc] initWithSocket:raw];
#endif
            curl_multi_assign(multi, raw, socket);
            CURLMultiLog(@"new socket:%@", socket);
        }

        [socket updateSourcesForSocket:raw mode:what multi:self];
        CURLMultiLog(@"updated socket:%@", socket);

        if (what == CURL_POLL_REMOVE)
        {
            NSAssert(socket != nil, @"should have socket");
            CURLMultiLog(@"removed socket:%@", socket);
#ifndef __clang_analyzer__
            [socket release];
            socket = nil;
#endif
            curl_multi_assign(multi, raw, nil);
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
#else

    // make a new queue for each CURLMulti instance
    NSString* name = [NSString stringWithFormat:@"com.karelia.CURLMulti.%p", self];
    queue = dispatch_queue_create([name UTF8String], NULL);

#endif

    return queue;
}

- (void)cleanupQueue
{
    dispatch_queue_t queue = self.queue;
    self.queue = nil;

#if !USE_GLOBAL_QUEUE // if we're using a global queue, we dont want to chuck it away
    // finally chuck away the queue
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_release(queue);
    });
#else
    (void)queue;
#endif

}
#pragma mark - Timer Management

- (BOOL)createTimer
{
    CURLM* multi = [self multiCreate];
    if (multi)
    {
        dispatch_queue_t queue = [self createQueue];
        if (queue)
        {
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

            dispatch_source_set_event_handler(timer, ^{
                CURLMultiLog(@"timer fired");
                [self processMulti:multi action:0 forSocket:CURL_SOCKET_TIMEOUT];
            });

            dispatch_source_set_cancel_handler(timer, ^{

                [self cleanupMulti:multi];

                CURLMultiLog(@"cancelled timer");
                dispatch_release(timer);

                [self cleanupQueue];
            });

            // kick things off - this should be enough to get the timer scheduled, but it won't actually start firing again until it is resumed
            dispatch_async(queue, ^{
                [self updateTimeout:0];
                //                [self processMulti:multi action:0 forSocket:CURL_SOCKET_TIMEOUT];
            });

            self.timer = timer;
            self.queue = queue;
        }
    }

    return multi && self.timer && self.queue;
}

#pragma mark - Callback Support

- (void)updateTimeout:(NSInteger)timeout
{
    // if multi is nil, the object is being thrown away
    if ([self notShutdown])
    {
        dispatch_source_t timer = self.timer;
        NSAssert(timer != nil, @"should still have a timer");

        // cap the timeout
        if ((timeout == -1) || (timeout > kMaximumTimeoutMilliseconds))
        {
            timeout = kMaximumTimeoutMilliseconds;
        }

        int64_t nano_timeout = timeout * NSEC_PER_MSEC;
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, nano_timeout, nano_timeout / 100);

        CURLMultiLog(@"timeout changed to %ldms", (long)timeout);
    }
}


- (NSString*)nameForType:(dispatch_source_type_t)type
{
    return (type == DISPATCH_SOURCE_TYPE_READ) ? @"reader" : @"writer";
}

- (dispatch_source_t)updateSource:(dispatch_source_t)source type:(dispatch_source_type_t)type socket:(int)socket required:(BOOL)required
{
    if (required)
    {
        if (!source)
        {
            CURLMultiLog(@"%@ dispatch source added for socket %d", [self nameForType:type], socket);
            source = dispatch_source_create(type, socket, 0, self.queue);

            CURLM* multi = self.multiForSocket;
            dispatch_source_set_event_handler(source, ^{
                if ([self notShutdown])
                {
                    int action = (type == DISPATCH_SOURCE_TYPE_READ) ? CURL_CSELECT_IN : CURL_CSELECT_OUT;
                    CURLMultiLog(@"%@ dispatch source fired for socket %d with value %ld", [self nameForType:type], socket, dispatch_source_get_data(source));
                    [self processMulti:multi action:action forSocket:socket];
                }
                else
                {
                    CURLMultiLog(@"%@ dispatch source fired  for socket %d on multi that has been shut down", [self nameForType:type], socket);
                }
            });

            dispatch_source_set_cancel_handler(source, ^{
                CURLMultiLog(@"%@ removed dispatch source for socket %d", [self nameForType:type], socket);
                dispatch_release(source);
            });

            dispatch_resume(source);
        }
    }
    else if (source)
    {
        CURLMultiLog(@"%@ removing dispatch source for socket %d", [self nameForType:type], socket);
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
    NSString* managing = [self.handles count] ? [NSString stringWithFormat:@": %@", [self.handles componentsJoinedByString:@","]] : @": no handles";
    return [NSString stringWithFormat:@"<MULTI %p%@>", self, managing];
}

#pragma mark - Callbacks


int timeout_callback(CURLM *multi, long timeout_ms, void *userp)
{
    CURLMulti* source = userp;
    [source updateTimeout:timeout_ms];

    return CURLM_OK;
}

int socket_callback(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp)
{
    CURLMulti* multi = userp;
    NSCAssert([multi findHandleWithEasyHandle:easy] != nil, @"socket callback for a handle %p that isn't managed by %@", easy, multi);

    [multi multiUpdateSocket:socketp raw:s what:what];
    
    return CURLM_OK;
}


@end
