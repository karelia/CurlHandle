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

@property (strong, nonatomic) NSMutableArray* handles;
@property (assign, atomic) CURLM* multi;
@property (assign, nonatomic) dispatch_queue_t queue;
@property (assign, nonatomic) dispatch_source_t timer;

- (void)updateTimeout:(NSInteger)timeout;
- (void)multiUpdateSocket:(CURLSocket*)socket raw:(curl_socket_t)raw what:(NSInteger)what;
- (void)multiProcessAction:(int)action forSocket:(int)socket;

@end

static int kMaximumTimeoutMilliseconds = 1000;

#pragma mark - Callback Prototypes

static int timeout_callback(CURLM *multi, long timeout_ms, void *userp);
static int socket_callback(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp);


@implementation CURLMulti

#pragma mark - Synthesized Properties

@synthesize handles = _handles;
@synthesize multi = _multi;
@synthesize queue = _queue;
@synthesize timer = _timer;

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
        if ([self multiCreate] == CURLM_OK)
        {
            self.handles = [NSMutableArray array];
            [self createQueue];
            [self createTimer];
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
    NSAssert((_multi == nil) && (_timer == nil) && (_queue == nil), @"should have been shut down by the time we're dealloced");

    [_handles release];

    [super dealloc];
}

#pragma mark - Startup / Shutdown

- (void)startup

{
    CURLHandleLog(@"started monitoring");
    dispatch_resume(self.timer);
}


- (void)shutdown
{
    // if the queue is gone, we've already been shut down and are probably being disposed
    dispatch_queue_t queue = self.queue;
    if (queue)
    {
        [self multiCleanup];
        CURLHandleLog(@"shutdown");
    }
    else
    {
        CURLHandleLog(@"shutdown called multiple times");
    }
}

#pragma mark - Easy Handle Management

- (void)manageHandle:(CURLHandle*)handle
{
    NSAssert(self.queue, @"need queue");
    NSAssert(self.handles, @"need handles");

    dispatch_async(self.queue, ^{
        [self multiAddHandle:handle];
    });
}

- (void)cancelHandle:(CURLHandle*)handle
{
    NSAssert(self.queue, @"need queue");

    [handle cancel];
    [handle completeWithMultiCode:CURLM_CANCELLED];
    dispatch_async(self.queue, ^{
        [self multiRemoveHandle:handle];
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

// Everything in this section should be called from our internal queue.

- (CURLM*)checkMulti
{
    NSAssert(self.queue == nil || dispatch_get_current_queue() == self.queue, @"should be running on our queue");

    return self.multi;
}


- (CURLMcode)multiCreate
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

        if (result == CURLM_OK)
        {
            self.multi = multi;
        }
    }

    return result;
}

- (void)multiCleanup
{
    // need to grab the multi here from the calling queue, because we're about to set self.multi to nil
    CURLM* multi = self.multi;

    dispatch_async(self.queue, ^{
        dispatch_source_cancel(self.timer);
        self.timer = nil;

        NSArray* handles = [self.handles retain];
        self.handles = nil; // stop removeHandle from mutating the array whilst we iterate through it
        for (CURLHandle* handle in handles)
        {
            [self removeHandle:handle fromMulti:multi];
        }
        [handles release];
        
        CURLMcode result = curl_multi_cleanup(multi);
        NSAssert(result == CURLM_OK, @"cleaning up multi failed unexpectedly with error %d", result);

        // finally chuck away the queue
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_release(self.queue);
            self.queue = nil;
        });
    });

    // clean out the multi straight away
    // various blocks may still be on the queue at this point, but they won't do anything
    // when they see that the multi variable has been zeroed
    self.multi = nil;
}

- (void)multiProcessAction:(int)action forSocket:(int)socket
{
    CURLMulti* multi = [self checkMulti];
    if (multi)
    {
        int running;
        CURLMcode result = curl_multi_socket_action(multi, socket, action, &running);
        if (result == CURLM_OK)
        {
            CURLMsg* message;
            int count;
            while ((message = curl_multi_info_read(multi, &count)) != NULL)
            {
                if (message->msg == CURLMSG_DONE)
                {
                    CURLHandleLog(@"got done msg result %d", message->data.result);
                    CURL* easy = message->easy_handle;
                    CURLHandle* handle = [self findHandleWithEasyHandle:easy];
                    if (handle)
                    {
                        [handle retain];
                        [handle completeWithCode:message->data.result];
                        [self removeHandle:handle fromMulti:multi];
                        [handle release];
                    }
                    else
                    {
                        // this really shouldn't happen - there should always be a matching CURLHandle - but just in case...
                        CURLHandleLog(@"seem to have an easy handle without a matching CURLHandle");
                        result = curl_multi_remove_handle(multi, message->easy_handle);
                        NSAssert(result == CURLM_OK, @"failed to remove curl easy from curl multi - something odd going on here");
                    }
                }
                else
                {
                    CURLHandleLog(@"got unexpected multi message %d", message->msg);
                }
            }
        }
        else
        {
            CURLHandleLog(@"curl_multi_socket_action returned error %d", result);
        }
    }

}

- (void)multiAddHandle:(CURLHandle*)handle
{
    NSAssert(![self.handles containsObject:handle], @"shouldn't add a handle twice");
    CURLMulti* multi = [self checkMulti];
    if (multi)
    {
        CURLMcode result = curl_multi_add_handle(multi, [handle curl]);
        if (result == CURLM_OK)
        {
            CURLHandleLog(@"added handle %@ (%p) to multi %@", handle, [handle curl], self);
            [self.handles addObject:handle];
        }
        else
        {
            CURLHandleLog(@"failed to add handle %@ (%p) to multi %@", handle, [handle curl], self);
            [handle completeWithMultiCode:result];
        }
    }

}

- (void)multiRemoveHandle:(CURL*)handle
{
    CURLMulti* multi = [self checkMulti];
    if (multi)
    {
        BOOL weOwnTheHandle = [self.handles containsObject:handle];
        NSAssert(weOwnTheHandle, @"should be managing the handle");
        if (weOwnTheHandle)
        {
            [self removeHandle:handle fromMulti:multi];
        }
    }
}

- (void)multiUpdateSocket:(CURLSocket*)socket raw:(curl_socket_t)raw what:(NSInteger)what
{
    CURLMulti* multi = [self checkMulti];
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
            socket = [[CURLSocket alloc] init];
#endif
            curl_multi_assign(multi, raw, socket);
            CURLHandleLog(@"new socket:%@", socket);
        }

        [socket updateSourcesForSocket:raw mode:what multi:self];

        if (what == CURL_POLL_REMOVE)
        {
            NSAssert(socket != nil, @"should have socket");
            CURLHandleLog(@"removed socket:%@", socket);
#ifndef __clang_analyzer__
            [socket release];
            socket = nil;
#endif
            curl_multi_assign(multi, raw, nil);
        }
    }
}

#pragma mark - Queue Management

- (void)createQueue
{
    NSString* name = [NSString stringWithFormat:@"com.karelia.CURLMulti.%p", self];
    self.queue = dispatch_queue_create([name UTF8String], NULL);
}

#pragma mark - Timer Management

- (void)createTimer
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    self.timer = timer;
    dispatch_source_set_event_handler(timer, ^{
#ifdef REDISPATCH_SOURCE_EVENT_TO_QUEUE
        if ([self notShutdown])
        {
            NSAssert(self.queue != nil, @"should still have queue");
            dispatch_async(self.queue, ^{
#endif
                [self multiProcessAction:CURL_SOCKET_TIMEOUT forSocket:0];
#ifdef REDISPATCH_SOURCE_EVENT_TO_QUEUE
            });
        }
#endif
    });

    dispatch_source_set_cancel_handler(self.timer, ^{
        CURLHandleLog(@"cancelled timer");
        dispatch_release(timer);
    });
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

        int64_t nano_timeout = timeout * 1000000LL;
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, nano_timeout, nano_timeout / 100);

        CURLHandleLog(@"timeout changed to %ldms", (long)timeout);
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
            CURLHandleLog(@"%@ added for socket %d", [self nameForType:type], socket);
            source = dispatch_source_create(type, socket, 0, self.queue);

            dispatch_source_set_event_handler(source, ^{
#if REDISPATCH_SOURCE_EVENT_TO_QUEUE
                if ([self notShutdown])
                {
                    NSAssert(self.queue != nil, @"should still have queue");
                    dispatch_async(self.queue, ^{
#endif
                        int action = (type == DISPATCH_SOURCE_TYPE_READ) ? CURL_CSELECT_IN : CURL_CSELECT_OUT;
                        [self multiProcessAction:action forSocket:socket];
#if REDISPATCH_SOURCE_EVENT_TO_QUEUE
                    });
                }
#endif
            });

            dispatch_source_set_cancel_handler(source, ^{
                CURLHandleLog(@"%@ removed for socket %d", [self nameForType:type], socket);
                dispatch_release(source);
            });

            dispatch_resume(source);
        }
    }
    else if (source)
    {
        dispatch_source_cancel(source);
        source = nil;
    }

    return source;
}

#pragma mark - Utilities

- (void)removeHandle:(CURLHandle*)handle fromMulti:(CURLMulti*)multi
{
    CURLHandleLog(@"removed handle %@ (%p) from multi %@", handle, [handle curl], self);
    CURLMcode result = curl_multi_remove_handle(multi, [handle curl]);
    NSAssert(result == CURLM_OK, @"failed to remove curl easy from curl multi - something odd going on here");
    [self.handles removeObject:handle];
}

- (BOOL)notShutdown
{
    return self.multi != nil;
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
    CURLMulti* source = userp;
    [source multiUpdateSocket:socketp raw:s what:what];
    
    return CURLM_OK;
}


@end
