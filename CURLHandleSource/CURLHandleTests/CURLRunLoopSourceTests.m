//
//  CURLRunLoopSourceTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLRunLoopSource.h"

#import <SenTestingKit/SenTestingKit.h>

@interface CURLRunLoopSource(PrivateUnitTestOnly)
- (CFRunLoopSourceRef)source;
@end

@interface CURLRunLoopSourceTests : SenTestCase

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

@end
