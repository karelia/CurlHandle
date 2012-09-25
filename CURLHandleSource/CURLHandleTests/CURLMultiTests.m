//
//  CURLMultiTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLMulti.h"
#import "CURLHandleBasedTest.h"

@interface CURLMultiTests : CURLHandleBasedTest

@end

@implementation CURLMultiTests

- (void)testStartupShutdown
{
    CURLMulti* multi = [[CURLMulti alloc] init];

    [multi startup];

    [multi shutdown];

    [multi release];
}

- (void)testHandleWithLoop
{
    CURLMulti* multi = [[CURLMulti alloc] init];

    [multi startup];

    CURLHandle* handle = [[CURLHandle alloc] init];
    handle.delegate = self;

    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];

    BOOL ok = [handle loadRequest:request withMulti:multi];
    STAssertTrue(ok, @"failed to load request");

    [self runUntilDone];

    [self checkDownloadedBufferWasCorrect];

    [handle release];

    [multi shutdown];

    [multi release];

}


- (void)testCancelling
{
    CURLMulti* multi = [[CURLMulti alloc] init];

    [multi startup];

    CURLHandle* handle = [[CURLHandle alloc] init];
    handle.delegate = self;

    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];

    BOOL ok = [handle loadRequest:request withMulti:multi];
    STAssertTrue(ok, @"failed to load request");

    [multi cancelHandle:handle];

    [self runUntilDone];

    STAssertTrue(self.cancelled, @"should have been cancelled");
    STAssertNil(self.response, @"should have no response");
    STAssertTrue([self.buffer length] == 0, @"should have no data");
    STAssertNil(self.error, @"got error %@", self.error);

    [handle release];

    [multi shutdown];
    
    [multi release];

}

@end
