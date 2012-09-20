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

@property (strong, nonatomic) __attribute__((NSObject)) CFRunLoopSourceRef source;
@property (strong, nonatomic) NSThread* thread;
@property (assign, nonatomic) CURLM* multi;

@end

#pragma mark - Callbacks

static void schedule(void *info, CFRunLoopRef rl, CFStringRef mode);
static void cancel(void *info, CFRunLoopRef rl, CFStringRef mode);
static void perform(void *info);

static void schedule(void *info, CFRunLoopRef rl, CFStringRef mode)
{
    CURLHandleLog(@"runloop scheduled for mode %@", mode);
}

static void cancel(void *info, CFRunLoopRef rl, CFStringRef mode)
{
    CURLHandleLog(@"runloop cancelled for mode %@", mode);
}

static void perform(void *info)
{
    CURLHandleLog(@"runloop performed");
}

@implementation CURLRunLoopSource

@synthesize source;

- (id)init
{
    if ((self = [super init]) != nil)
    {

    }

    return self;
}

- (void)dealloc
{
    [self shutdown];
    
    [_thread release];

    [super dealloc];
}

- (void)addToRunLoop:(NSRunLoop*)runLoop
{
    [self addToRunLoop:runLoop mode:(NSString*)kCFRunLoopCommonModes];
}

- (void)removeFromRunLoop:(NSRunLoop*)runLoop
{
    [self removeFromRunLoop:runLoop mode:(NSString*)kCFRunLoopCommonModes];
}

- (void)addToRunLoop:(NSRunLoop*)runLoop mode:(NSString*)mode;

{
    if ([self createSource])
    {
        CFRunLoopRef cf = [runLoop getCFRunLoop];
        CFRunLoopAddSource(cf, self.source, (CFStringRef)mode);
        [self createThread];
    }
}

- (void)removeFromRunLoop:(NSRunLoop*)runLoop mode:(NSString*)mode;
{
    CFRunLoopRef cf = [runLoop getCFRunLoop];
    CFRunLoopRemoveSource(cf, self.source, (CFStringRef)mode);
}

- (void)shutdown
{
    [self releaseThread];
    [self releaseSource];
    CURLHandleLog(@"shutdown");
}

- (BOOL)createSource
{
    if (self.source == nil)
    {
        CFRunLoopSourceContext context;
        memset(&context, 0, sizeof(context));
        context.info = self;
        context.schedule = schedule;
        context.perform = perform;
        context.cancel = cancel;
        self.source = CFRunLoopSourceCreate(nil, 0, &context);
        CURLHandleLog(self.source ? @"created source" : @"failed to create source");

    }

    return (self.source != nil);
}

- (void)releaseSource
{
    if (self.source)
    {
        CFRunLoopSourceInvalidate(self.source);
        self.source = nil;
        CURLHandleLog(@"released source");
    }
}

- (BOOL)createThread
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

    CURLHandleLog(@"finished monitor thread");
}

@end
