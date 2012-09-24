//
//  CURLRunLoopSourceTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLRunLoopSource.h"
#import "CURLHandleBasedTest.h"

@interface CURLRunLoopSource(PrivateUnitTestOnly)
- (CFRunLoopSourceRef)source;
@end

@interface CURLRunLoopSourceTests : CURLHandleBasedTest

@end

@implementation CURLRunLoopSourceTests

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

    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];

    BOOL ok = [handle loadRequest:request usingSource:source];
    STAssertTrue(ok, @"failed to load request");

    [self runUntilDone];

    [self checkDownloadedBufferWasCorrect];

    [handle release];

    [source removeFromRunLoop:runLoop];
    sourceAttachedToLoop = CFRunLoopContainsSource(cf, [source source], kCFRunLoopDefaultMode);

    [source shutdown];

    [source release];

}
@end
