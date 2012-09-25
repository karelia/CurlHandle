//
//  CURLProtocolTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "NSURLRequest+CURLHandle.h"
#import "CURLHandleBasedTest.h"

@interface CURLProtocolTests : CURLHandleBasedTest<NSURLConnectionDelegate, NSURLConnectionDataDelegate>

@end

@implementation CURLProtocolTests

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    self.error = error;
    self.exitRunLoop = YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.response = response;
    self.buffer = [NSMutableData data];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)dataIn
{
    [self.buffer appendData:dataIn];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    self.exitRunLoop = YES;
}

- (void)testSimpleDownload
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];
    request.shouldUseCurlHandle = YES;

    NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
    
    STAssertNotNil(connection, @"failed to get connection for request %@", request);

    [self runUntilDone];

    [self checkDownloadedBufferWasCorrect];
}

- (void)testCancelling
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];
    request.shouldUseCurlHandle = YES;

    NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];

    STAssertNotNil(connection, @"failed to get connection for request %@", request);

    [connection cancel];
}

@end
