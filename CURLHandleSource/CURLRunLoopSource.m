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
@property (assign, atomic) BOOL handleAdded;
@property (strong, nonatomic) NSMutableArray* handles;
@property (assign, nonatomic) struct timeval timeout;

@end

#pragma mark - Callbacks

static void schedule(void *info, CFRunLoopRef rl, CFStringRef mode);
static void cancel(void *info, CFRunLoopRef rl, CFStringRef mode);
static void perform(void *info);
static int timeout_changed(CURLM *multi, long timeout_ms, void *userp);

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

@synthesize source;

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

- (BOOL)addHandle:(CURLHandle*)handle
{
    [self.handles addObject:handle];
    CURLMcode result = curl_multi_add_handle(self.multi, [handle curl]);
    self.handleAdded = YES;

    return result == CURLM_OK;
}

- (BOOL)removeHandle:(CURLHandle*)handle
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

    curl_multi_setopt(multi, CURLMOPT_TIMERFUNCTION, timeout_changed);
    curl_multi_setopt(multi, CURLMOPT_TIMERDATA, self);
    
    static int MAX_FDS = 128;
    fd_set read_fds;
    fd_set write_fds;
    fd_set exc_fds;
    int count = MAX_FDS;


    while (![self.thread isCancelled])
    {
        if (self.handleAdded)
        {
            curl_multi_perform(multi, &count);
            self.handleAdded = NO;
        }
        
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
                        [handle completeForRunLoopSource:self];
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
