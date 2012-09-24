//
//  CURLHandleTests.m
//  CURLHandleTests
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLHandleBasedTest.h"

@interface CURLHandleTests : CURLHandleBasedTest

@end

@implementation CURLHandleTests

- (void)testSimpleDownload
{
    CURLHandle* handle = [[CURLHandle alloc] init];
    handle.delegate = self;

    NSError* error = nil;
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];

    BOOL ok = [handle loadRequest:request error:&error];
    STAssertTrue(ok, @"failed to load request, with error %@", error);

    [self checkDownloadedBufferWasCorrect];

    [handle release];
}

@end
