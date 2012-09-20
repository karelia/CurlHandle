//
//  CURLRunLoopSource.m
//  CURLHandle
//
//  Created by Sam Deane on 20/09/2012.
//
//

#import "CURLRunLoopSource.h"

#import "CURLHandle.h"

@interface CURLRunLoopSource()

@property (assign, nonatomic) CFRunLoopSourceRef source;
@property (strong, nonatomic) NSThread* thread;
@property (assign, atomic) BOOL running;
@property (assign, nonatomic) CURLM* multi;

@end

#pragma mark - Callbacks

static void schedule(void *info, CFRunLoopRef rl, CFStringRef mode);
static void cancel(void *info, CFRunLoopRef rl, CFStringRef mode);
static void perform(void *info);

static void schedule(void *info, CFRunLoopRef rl, CFStringRef mode)
{
    CURLHandleLog(@"runloop scheduled");
}

static void cancel(void *info, CFRunLoopRef rl, CFStringRef mode)
{
    CURLHandleLog(@"runloop cancelled");
}

static void perform(void *info)
{
    CURLHandleLog(@"runloop performed");
}

@implementation CURLRunLoopSource

@synthesize source;

- (BOOL)createSource
{
    CFRunLoopSourceContext context;
    memset(&context, 0, sizeof(context));
    context.info = self;
    context.schedule = schedule;
    context.perform = perform;
    context.cancel = cancel;
    self.source = CFRunLoopSourceCreate(nil, 0, &context);

    return (self.source != nil);
}

- (void)releaseSource
{
    if (self.source)
    {
        CFRelease(self.source);
        self.source = nil;
    }
}

- (void)createThread
{
    self.thread = [[NSThread alloc] initWithTarget:self selector:@selector(monitor) object:nil];
}

- (void)monitor
{
    CURLM* multi = curl_multi_init();
    self.multi = multi;

    static int MAX_FDS = 128;
    fd_set read_fds;
    fd_set write_fds;
    fd_set exc_fds;
    int count = MAX_FDS;

    while (self.running)
    {
        FD_ZERO(read_fds);
        FD_ZERO(write_fds);
        FD_ZERO(exc_fds);
        count = FD_SETSIZE;
        CURLMcode result = curl_multi_fdset(multi, &read_fds, &write_fds, &exc_fds, &count);
        if (result == CURLM_OK)
        {
            long timeoutMilliseconds;
            curl_multi_timeout(multi, &timeoutMilliseconds);
            struct timeval timeout;
            timeout.tv_sec = timeoutMilliseconds / 1000;
            timeout.tv_usec = (timeoutMilliseconds % 1000) * 1000;

            int ready = select(count, &read_fds, &write_fds, &exc_fds, &timeout);
            if (ready > 0)
            {
                curl_multi_perform(multi, &count);

                CURLMsg* message;
                while ((message = curl_multi_info_read(multi, &count)) != nil)
                {
                    if (message->msg == CURLMSG_DONE)
                    {
                        curl_multi_remove_handle(multi, message->easy_handle);
                    }
                }
            }
        }
    }

    self.multi = nil;
    curl_multi_cleanup(multi);
}

@end
