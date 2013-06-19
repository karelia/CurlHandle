//
//  CURLProtocolTests.m
//  CURLHandle
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import "CURLProtocol.h"
#import "CURLRequest.h"

#import "CURLHandleBasedTest.h"

@interface CURLProtocolTests : CURLHandleBasedTest<NSURLConnectionDelegate, NSURLConnectionDataDelegate>

@property (assign, nonatomic) BOOL pauseOnResponse;

@end

@implementation CURLProtocolTests

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"failed with error %@", error);

    self.error = error;
    [self pause];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSLog(@"got response %@", response);

    self.response = response;
    self.buffer = [NSMutableData data];
    if (self.pauseOnResponse)
    {
        [self pause];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)dataIn
{
    NSLog(@"got data %ld bytes", [dataIn length]);

    [self.buffer appendData:dataIn];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSLog(@"finished");

    [self pause];
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite;
{
    self.sending = YES;
}

- (void)testHTTPDownload
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[self testFileRemoteURL]];
    request.shouldUseCurlHandle = YES;

    NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
    
    STAssertNotNil(connection, @"failed to get connection for request %@", request);

    [self runUntilPaused];

    [self checkDownloadedBufferWasCorrect];
}

- (void)testCancelling
{
    self.pauseOnResponse = YES;
    NSURL* largeFile = [NSURL URLWithString:@"https://github.com/karelia/CurlHandle/archive/master.zip"];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:largeFile];
    request.shouldUseCurlHandle = YES;

    NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
    STAssertNotNil(connection, @"failed to get connection for request %@", request);

    [self runUntilPaused];

    [connection cancel];

    // we don't get any delegate message to say that we've been cancelled, so we just have to finish
    // the test here without checking anything else
}

- (void)testFTPDownload
{
    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        NSURL* ftpDownload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"TestContent.txt"];

        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpDownload];
        request.shouldUseCurlHandle = YES;

        NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
        STAssertNotNil(connection, @"failed to get connection for request %@", request);

        [self runUntilPaused];
        
        [self checkDownloadedBufferWasCorrect];
    }
}

- (void)testFTPUpload
{
    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        NSURL* ftpUpload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"Upload.txt"];

        NSError* error = nil;
        NSURL* testNotesURL = [self testFileURL];
        NSString* testNotes = [NSString stringWithContentsOfURL:testNotesURL encoding:NSUTF8StringEncoding error:&error];

        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpUpload];
        request.shouldUseCurlHandle = YES;
        [request curl_setCreateIntermediateDirectories:1];
        [request setHTTPBody:[testNotes dataUsingEncoding:NSUTF8StringEncoding]];

        NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
        STAssertNotNil(connection, @"failed to get connection for request %@", request);

        [self runUntilPaused];

        NSURLResponse* response = self.response;
        if ([response respondsToSelector:@selector(statusCode)])
        {
            NSUInteger code = [(id)response statusCode];
            STAssertEquals(code, (NSInteger) 226, @"got unexpected code %ld", code);
            STAssertNil(self.error, @"got error %@", self.error);
            STAssertTrue([self.buffer length] == 0, @"got unexpected data %@", self.buffer);
        }
    }
}

@end
