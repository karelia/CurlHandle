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

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite;
{
    self.sending = YES;
}

- (void)testHTTPDownload
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

- (void)testFTPDownload
{
    NSString* ftpTest = [[NSUserDefaults standardUserDefaults] objectForKey:@"CURLHandleFTPTestURL"];
    STAssertNotNil(ftpTest, @"need to set a test server address using defaults, e.g: defaults write otest CURLHandleFTPTestURL \"ftp://user:password@ftp.test.com\"");

    NSURL* ftpRoot = [NSURL URLWithString:ftpTest];
    NSURL* ftpDownload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"DevNotes.txt"];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpDownload];
    request.shouldUseCurlHandle = YES;

    NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
    STAssertNotNil(connection, @"failed to get connection for request %@", request);

    [self runUntilDone];

    [self checkDownloadedBufferWasCorrect];
}

- (void)testFTPUpload
{
    NSString* ftpTest = [[NSUserDefaults standardUserDefaults] objectForKey:@"CURLHandleTestsFTPServer"];
    STAssertNotNil(ftpTest, @"need to set a test server address using defaults, e.g: defaults write otest CURLHandleTestsFTPServer \"ftp://user:password@ftp.test.com\"");

    NSURL* ftpRoot = [NSURL URLWithString:ftpTest];
    NSURL* ftpUpload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"Upload.txt"];

    NSError* error = nil;
    NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
    NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpUpload];
    request.shouldUseCurlHandle = YES;
    [request curl_setCreateIntermediateDirectories:1];
    [request setHTTPBody:[devNotes dataUsingEncoding:NSUTF8StringEncoding]];

    NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
    STAssertNotNil(connection, @"failed to get connection for request %@", request);

    [self runUntilDone];

    STAssertNil(self.error, @"got error %@", self.error);
    STAssertNil(self.response, @"got unexpected response %@", self.response);
    STAssertTrue([self.buffer length] == 0, @"got unexpected data %@", self.buffer);
}

@end
