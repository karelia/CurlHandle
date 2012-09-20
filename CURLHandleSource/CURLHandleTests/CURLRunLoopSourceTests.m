//
//  CURLHandleTests.m
//  CURLHandleTests
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLRunLoopSource.h"

#import <SenTestingKit/SenTestingKit.h>

@interface CURLHandleTests : SenTestCase

@end

@implementation CURLHandleTests

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

    [source removeFromRunLoop:runLoop];

    [source shutdown];
    
    [source release];
}

@end
