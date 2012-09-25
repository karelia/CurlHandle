//
//  CURLMulti.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLMulti.h"

#import "CURLHandle.h"

@interface CURLMulti()

#pragma mark - Private Properties

@property (assign, nonatomic) BOOL cancelled;
@property (strong, nonatomic) NSMutableArray* handles;
@property (assign, nonatomic) CURLM* multi;
@property (assign, nonatomic) dispatch_queue_t queue;
@property (assign, nonatomic) struct timeval timeout;

- (void)updateTimeout:(NSInteger)timeout;

@end

static int kMaximumTimeoutMilliseconds = 1000;

#pragma mark - Callback Prototypes

static int timeout_callback(CURLM *multi, long timeout_ms, void *userp);
static int socket_callback(CURL *easy, curl_socket_t s, int what, void *userp, void *socketp);


@implementation CURLMulti

#pragma mark - Synthesized Properties

@synthesize cancelled = _cancelled;
@synthesize handles = _handles;
@synthesize multi = _multi;
@synthesize queue = _queue;
@synthesize timeout = _timeout;

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
        if ([self createMulti] == CURLM_OK)
        {
            self.handles = [NSMutableArray array];
            self.queue = dispatch_queue_create("com.karelia.CURLMulti", NULL);
            dispatch_set_target_queue(self.queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
            struct timeval timeout;
            timeout.tv_sec = 0;
            timeout.tv_usec = 1000;
            self.timeout = timeout;
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
    [self shutdown];

    [_handles release];

    [super dealloc];
}

#pragma mark - Startup / Shutdown

- (void)startup

{
    CURLHandleLog(@"started monitoring");
    [self monitorMulti];
}


- (void)shutdown
{
    if (self.multi)
    {
        [self removeAllHandles];
        self.cancelled = YES;

        dispatch_queue_t queue = self.queue;
        dispatch_sync(queue, ^{
            [self releaseMulti];
        });

        self.queue = nil;
        dispatch_release(queue);
        
        CURLHandleLog(@"shutdown");
    }
}

#pragma mark - Easy Handle Management

- (void)addHandle:(CURLHandle*)handle
{
    dispatch_async(self.queue, ^{
        CURLMcode result = curl_multi_add_handle(self.multi, [handle curl]);
        if (result == CURLM_OK)
        {
            CURLHandleLog(@"added handle %@ to multi %@", handle, self);
            [self.handles addObject:handle];
        }
        else
        {
            CURLHandleLog(@"failed to add handle %@ to multi %@", handle, self);
            [handle completeWithCode:result];
        }
    });
}

- (void)removeHandle:(CURLHandle*)handle
{
    dispatch_async(self.queue, ^{
        [self removeHandleInternal:handle];
    });

}

- (void)cancelHandle:(CURLHandle*)handle
{
    dispatch_async(self.queue, ^{
        [handle retain];
        [self removeHandleInternal:handle];
        [handle cancel];
        [handle completeWithCode:CURLM_CANCELLED];
        [handle release];
    });

}

- (void)removeHandleInternal:(CURLHandle*)handle
{
    CURLHandleLog(@"removed handle %@ from multi %@", handle, self);
    CURLMcode result = curl_multi_remove_handle(self.multi, [handle curl]);
    NSAssert(result == CURLM_OK, @"failed to remove curl easy from curl multi - something odd going on here");
    [self.handles removeObject:handle];
}

- (CURLHandle*)findHandleWithEasyHandle:(CURL*)easy
{
    CURLHandle* result = nil;
    for (CURLHandle* handle in self.handles)
    {
        if ([handle curl] == easy)
        {
            result = handle;
            break;
        }
    }

    return result;
}

- (void)removeAllHandles
{
    NSArray* handles = [self.handles copy];
    dispatch_sync(self.queue, ^{
        for (CURLHandle* handle in handles)
        {
            [self removeHandleInternal:handle];
        }

    });

    // we may be the last thing holding on to the handles
    // curl should be finished with them by now, but for safety's sake we autorelease our
    // array copy
    [handles autorelease];
}

#pragma mark - Multi Handle Management

- (CURLMcode)createMulti
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

//        if (result == CURLM_OK)
//        {
//            result = curl_multi_setopt(multi, CURLMOPT_SOCKETFUNCTION, socket_callback);
//        }
//
//        if (result == CURLM_OK)
//        {
//            result = curl_multi_setopt(multi, CURLMOPT_SOCKETDATA, self);
//        }

        if (result == CURLM_OK)
        {
            self.multi = multi;
        }
    }

    return result;
}

- (void)releaseMulti
{
    CURLHandleLog(@"released multi %@", self);

    CURLMcode result = curl_multi_cleanup(self.multi);
    NSAssert(result == CURLM_OK, @"cleaning up multi failed unexpectedly with error %d", result);
    self.multi = nil;
}

- (void)monitorMulti
{
//    int running;
//    curl_multi_socket_action(self.multi, CURL_SOCKET_TIMEOUT, 0, &running);
    
    static int MAX_FDS = 128;
    fd_set read_fds;
    fd_set write_fds;
    fd_set exc_fds;
    int count = MAX_FDS;
    CURLMcode result;

    FD_ZERO(&read_fds);
    FD_ZERO(&write_fds);
    FD_ZERO(&exc_fds);
    count = FD_SETSIZE;
    result = curl_multi_fdset(self.multi, &read_fds, &write_fds, &exc_fds, &count);

    if (result == CURLM_OK)
    {
        struct timeval timeout = self.timeout;
        count = select(count + 1, &read_fds, &write_fds, &exc_fds, &timeout);
        result = curl_multi_perform(self.multi, &count);

        CURLMsg* message;
        while ((message = curl_multi_info_read(self.multi, &count)) != nil)
        {
            CURLHandleLog(@"got multi message %d", message->msg);
            if (message->msg == CURLMSG_DONE)
            {
                CURLHandle* handle = [self findHandleWithEasyHandle:message->easy_handle];
                if (handle)
                {
                    [handle retain];
                    [self removeHandleInternal:handle];
                    [handle completeWithCode:CURLM_OK];
                    [handle release];
                }
                else
                {
                    // this really shouldn't happen - there should always be a matching CURLHandle - but just in case...
                    CURLHandleLog(@"seem to have an easy handle without a matching CURLHandle");
                    result = curl_multi_remove_handle(self.multi, message->easy_handle);
                }
            }
        }
    }

    if (result != CURLM_OK)
    {
        CURLHandleLog(@"curl error encountered whilst monitoring multi %d", result);
    }

    if ((result == CURLM_OK) && !self.cancelled)
    {
        dispatch_async(self.queue, ^{
            [self monitorMulti];
        });
    }
}

#pragma mark - Callback Support

- (void)updateTimeout:(NSInteger)timeout
{
    // cap the timeout
    if ((timeout == -1) || (timeout > kMaximumTimeoutMilliseconds))
    {
        timeout = kMaximumTimeoutMilliseconds;
    }

    struct timeval tv;
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = (timeout % 1000) * 1000;
    self.timeout = tv;

    CURLHandleLog(@"timeout changed to %ldms", timeout);
}

- (void)updateSocket:(curl_socket_t)socket what:(NSInteger)what source:(dispatch_source_t)source
{
    CURLHandleLog(@"socket callback what: %ld socket: %p", what, (void*) socket);
    if (!source)
    {
        source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, socket, 0, self.queue);
    }
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
    [source updateSocket:s what:what source:socketp];

    return CURLM_OK;
}


@end
