//
//  CURLRunLoopSource.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLRunLoopSource.h"

#import "CURLHandle.h"

@interface CURLRunLoopSource()

@property (strong, nonatomic) NSThread* thread;
@property (assign, nonatomic) CURLM* multi;
@property (strong, nonatomic) NSMutableArray* handles;
@property (assign, nonatomic) struct timeval timeout;

@end

#pragma mark - Callbacks

static int timeout_changed(CURLM *multi, long timeout_ms, void *userp);

int timeout_changed(CURLM *multi, long timeout_ms, void *userp)
{
    CURLRunLoopSource* source = userp;

    struct timeval timeout;
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    source.timeout = timeout;

    CURLHandleLog(@"timeout changed to %ldms", timeout_ms);

    return CURLM_OK;
}

@implementation CURLRunLoopSource

@synthesize handles = _handles;
@synthesize multi = _multi;
@synthesize thread = _thread;
@synthesize timeout = _timeout;

- (id)init
{
    if ((self = [super init]) != nil)
    {
        self.handles = [NSMutableArray array];
        struct timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 1000;
        self.timeout = timeout;
    }

    return self;
}

- (void)dealloc
{
    [self shutdown];

    [_handles release];
    [_thread release];

    [super dealloc];
}

- (void)startup

{
    [self createThread];
}

- (BOOL)addHandle:(CURLHandle*)handle error:(NSError**)error
{
    [self.handles addObject:handle];
    CURLMcode result = curl_multi_add_handle(self.multi, [handle curl]);

    return result == CURLM_OK;
}

- (BOOL)removeHandle:(CURLHandle*)handle error:(NSError**)error
{
    CURLMcode result = curl_multi_remove_handle(self.multi, [handle curl]);
    [self.handles removeObject:handle];

    return result == CURLM_OK;
}

- (CURLHandle*)handleWithEasyHandle:(CURL*)easy
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
    for (CURLHandle* handle in self.handles)
    {
        curl_multi_remove_handle(self.multi, [handle curl]);
    }

    [self.handles removeAllObjects];
}

- (void)shutdown
{
    [self removeAllHandles];
    [self releaseThread];
    CURLHandleLog(@"shutdown");
}

- (BOOL)createThread // TODO: turn this into getter
{
    if (!self.thread)
    {
        NSThread* thread = [[NSThread alloc] initWithTarget:self selector:@selector(monitor) object:nil];
        self.thread = thread;
        [thread start];
        [thread release];
        CURLHandleLog(thread ? @"created thread" : @"failed to create thread");
    }

    return (self.thread != nil);
}

- (void)releaseThread
{
    if (self.thread)
    {
        [self.thread cancel];
        while (![self.thread isFinished])
        {
            // TODO: spin runloop here?
        }

        self.thread = nil;
        CURLHandleLog(@"released thread");
    }
}

- (void)monitor
{
    CURLHandleLog(@"started monitor thread");

    CURLM* multi = curl_multi_init();
    self.multi = multi;

    curl_multi_setopt(multi, CURLMOPT_TIMERFUNCTION, timeout_changed);
    curl_multi_setopt(multi, CURLMOPT_TIMERDATA, self);
    
    static int MAX_FDS = 128;
    fd_set read_fds;
    fd_set write_fds;
    fd_set exc_fds;
    int count = MAX_FDS;


    while (![self.thread isCancelled])
    {
        FD_ZERO(&read_fds);
        FD_ZERO(&write_fds);
        FD_ZERO(&exc_fds);
        count = FD_SETSIZE;
        CURLMcode result = curl_multi_fdset(multi, &read_fds, &write_fds, &exc_fds, &count);
        if (result == CURLM_OK)
        {
            struct timeval timeout = self.timeout;
            count = select(count + 1, &read_fds, &write_fds, &exc_fds, &timeout);
            curl_multi_perform(multi, &count);

            CURLMsg* message;
            while ((message = curl_multi_info_read(multi, &count)) != nil)
            {
                CURLHandleLog(@"got multi message %d", message->msg);
                if (message->msg == CURLMSG_DONE)
                {
                    CURLHandle* handle = [self handleWithEasyHandle:message->easy_handle];
                    if (handle)
                    {
                        [handle completeUsingSource:self];
                    }
                    else
                    {
                        // this really shouldn't happen - there should always be a matching CURLHandle - but just in case...
                        CURLHandleLog(@"seem to have an easy handle without a matching CURLHandle");
                        curl_multi_remove_handle(multi, message->easy_handle);
                    }
                }
            }
        }
    }

    self.multi = nil;
    curl_multi_cleanup(multi);

    CURLHandleLog(@"finished monitor thread");
}


@end
