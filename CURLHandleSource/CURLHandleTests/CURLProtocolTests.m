//
//  CURLProtocolTests.m
//  CURLProtocolTests
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLProtocol.h"
#import "CURLHandleBasedTest.h"

@interface CURLProtocolTests : CURLHandleBasedTest

@end

@implementation CURLProtocolTests

- (void)testSimpleDownload
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];
    request.shouldUseCurlHandle = YES;

    NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
    
    STAssertNotNil(connection, @"failed to get connection for request %@", request);

    [self runUntilDone];

    [self checkDownloadedBufferWasCorrect];
}

@end
