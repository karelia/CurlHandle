//
//  CURLRunLoopSourceTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLRunLoopSource.h"
#import "CURLHandle.h"

#import <SenTestingKit/SenTestingKit.h>

@interface CURLRunLoopSource(PrivateUnitTestOnly)
- (CFRunLoopSourceRef)source;
@end

@interface CURLRunLoopSourceTests : SenTestCase<CURLHandleDelegate>

@property (strong, nonatomic) NSMutableData* buffer;
@property (assign, nonatomic) NSUInteger expected;
@property (assign, atomic) BOOL exitRunLoop;
@property (strong, nonatomic) NSURLResponse* response;
@property (assign, nonatomic) BOOL sending;


@end

@implementation CURLRunLoopSourceTests

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data
{
    NSMutableData* buffer = self.buffer;
    if (!buffer)
    {
        buffer = [NSMutableData dataWithCapacity:self.expected];
        self.buffer = buffer;
    }

    [buffer appendData:data];

    self.exitRunLoop = [buffer length] == self.expected;
}

- (void)handle:(CURLHandle *)handle didReceiveResponse:(NSURLResponse *)response
{
    self.response = response;
    self.expected = response.expectedContentLength;
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    self.sending = YES;
}

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type
{
    CURLHandleLog(@"got debug info: %@ type:%d", string, type);
}

- (void)testAddingLoop
{
    CURLRunLoopSource* source = [[CURLRunLoopSource alloc] init];

    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];

    [source addToRunLoop:runLoop];

    CFRunLoopRef cf = [runLoop getCFRunLoop];
    BOOL sourceAttachedToLoop = CFRunLoopContainsSource(cf, [source source], kCFRunLoopDefaultMode);
    STAssertTrue(sourceAttachedToLoop, @"added source to runloop");

    [source removeFromRunLoop:runLoop];
    sourceAttachedToLoop = CFRunLoopContainsSource(cf, [source source], kCFRunLoopDefaultMode);
    STAssertFalse(sourceAttachedToLoop, @"removed source from runloop");

    [source shutdown];
    
    [source release];
}

- (void)testHandleWithLoop
{
    CURLRunLoopSource* source = [[CURLRunLoopSource alloc] init];

    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];

    [source addToRunLoop:runLoop];

    CFRunLoopRef cf = [runLoop getCFRunLoop];
    BOOL sourceAttachedToLoop = CFRunLoopContainsSource(cf, [source source], kCFRunLoopDefaultMode);

    CURLHandle* handle = [[CURLHandle alloc] init];
    handle.delegate = self;

    NSError* error = nil;
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];

    BOOL ok = [handle loadRequest:request forRunLoopSource:source error:&error];
    STAssertTrue(ok, @"failed to load request, with error %@", error);

    self.exitRunLoop = NO;
    while (!self.exitRunLoop)
    {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
    }

    STAssertNotNil(self.response, @"got no response");
    STAssertTrue([self.buffer length] > 0, @"got no data");

    NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
    NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];
    NSString* receivedNotes = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
    STAssertTrue([receivedNotes isEqualToString:devNotes], @"received notes didn't match: was:\n%@\n\nshould have been:\n%@", receivedNotes, devNotes);

    [handle release];

    [source removeFromRunLoop:runLoop];
    sourceAttachedToLoop = CFRunLoopContainsSource(cf, [source source], kCFRunLoopDefaultMode);

    [source shutdown];

    [source release];

}
@end
