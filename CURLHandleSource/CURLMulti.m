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
@property (strong, nonatomic) NSOperationQueue* queue;
@property (assign, nonatomic) struct timeval timeout;

@end

#pragma mark - Callbacks

static int kMaximumTimeoutMilliseconds = 1000;

static int timeout_changed(CURLM *multi, long timeout_ms, void *userp);

int timeout_changed(CURLM *multi, long timeout_ms, void *userp)
{
    CURLMulti* source = userp;

    // cap the timeout
    if ((timeout_ms == -1) || (timeout_ms > kMaximumTimeoutMilliseconds))
    {
        timeout_ms = kMaximumTimeoutMilliseconds;
    }

    struct timeval timeout;
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    source.timeout = timeout;

    CURLHandleLog(@"timeout changed to %ldms", timeout_ms);

    return CURLM_OK;
}

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
            NSOperationQueue* queue = [[NSOperationQueue alloc] init];
            queue.maxConcurrentOperationCount = 1;
            self.queue = queue;
            [queue release];
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
    [_queue release];

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
        [self.queue waitUntilAllOperationsAreFinished];

        [self releaseMulti];
        CURLHandleLog(@"shutdown");
    }
}

#pragma mark - Easy Handle Management

- (void)addHandle:(CURLHandle*)handle
{
    [self.queue addOperationWithBlock:^{
        CURLMcode result = curl_multi_add_handle(self.multi, [handle curl]);
        if (result == CURLM_OK)
        {
            [self.handles addObject:handle];
        }
        else
        {
            [handle completeWithCode:result];
        }
    }];
}

- (void)removeHandle:(CURLHandle*)handle
{
    [self.queue addOperationWithBlock:^{
        [self removeHandleInternal:handle];
    }];

}

- (void)cancelHandle:(CURLHandle*)handle
{
    [self.queue addOperationWithBlock:^{
        [handle retain];
        [self removeHandleInternal:handle];
        [handle cancel];
        [handle completeWithCode:CURLM_CANCELLED];
        [handle release];
    }];

}

- (void)removeHandleInternal:(CURLHandle*)handle
{
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
    [self.queue addOperationWithBlock:^{
        for (CURLHandle* handle in self.handles)
        {
            curl_multi_remove_handle(self.multi, [handle curl]);
        }

        [self.handles removeAllObjects];
    }];
}

#pragma mark - Multi Handle Management

- (CURLMcode)createMulti
{
    CURLMcode result = CURLM_OK;
    CURLM* multi = curl_multi_init();
    if (multi)
    {
        result = curl_multi_setopt(multi, CURLMOPT_TIMERFUNCTION, timeout_changed);
        if (result == CURLM_OK)
        {
            result = curl_multi_setopt(multi, CURLMOPT_TIMERDATA, self);
            if (result == CURLM_OK)
            {
                self.multi = multi;
            }
        }
    }

    return result;
}

- (void)releaseMulti
{
    curl_multi_cleanup(self.multi);
    self.multi = nil;
}

- (void)monitorMulti
{
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
        [self.queue addOperationWithBlock:^{
            [self monitorMulti];
        }];
    }
}


@end
