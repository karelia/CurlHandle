//
//  CURLMultiTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLMulti.h"
#import "CURLHandleBasedTest.h"

#import "NSURLRequest+CURLHandle.h"

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

- (void)testHTTPUpload
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

- (void)testFTPDownload
{
    CURLMulti* multi = [[CURLMulti alloc] init];

    [multi startup];
    
    NSURL* ftpRoot = [self ftpTestServer];
    NSURL* ftpDownload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"DevNotes.txt"];

    CURLHandle* handle = [[CURLHandle alloc] init];
    handle.delegate = self;

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpDownload];

    BOOL ok = [handle loadRequest:request withMulti:multi];
    STAssertTrue(ok, @"failed to load request");

    [self runUntilDone];

    [self checkDownloadedBufferWasCorrect];

    [multi shutdown];

    [handle release];

    [multi release];
}

//- (void)testFTPUpload
//{
//    CURLMulti* multi = [[CURLMulti alloc] init];
//
//    [multi startup];
//    
//    NSURL* ftpRoot = [self ftpTestServer];
//    NSURL* ftpUpload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"Upload.txt"];
//
//    NSError* error = nil;
//    NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
//    NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];
//
//    CURLHandle* handle = [[CURLHandle alloc] init];
//    handle.delegate = self;
//
//    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpUpload];
//    request.shouldUseCurlHandle = YES;
//    [request curl_setCreateIntermediateDirectories:1];
//    [request setHTTPBody:[devNotes dataUsingEncoding:NSUTF8StringEncoding]];
//
//    BOOL ok = [handle loadRequest:request withMulti:multi];
//    STAssertTrue(ok, @"failed to load request");
//
//    [self runUntilDone];
//    
//    STAssertTrue(self.sending, @"should have set sending flag");
//    STAssertNil(self.error, @"got error %@", self.error);
//    STAssertNil(self.response, @"got unexpected response %@", self.response);
//    STAssertTrue([self.buffer length] == 0, @"got unexpected data %@", self.buffer);
//
//    [handle release];
//
//    [multi shutdown];
//
//    [multi release];
//
//}
//
//- (void)testCancelling
//{
//    CURLMulti* multi = [[CURLMulti alloc] init];
//
//    [multi startup];
//
//    CURLHandle* handle = [[CURLHandle alloc] init];
//    handle.delegate = self;
//
//    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];
//
//    BOOL ok = [handle loadRequest:request withMulti:multi];
//    STAssertTrue(ok, @"failed to load request");
//
//    [multi cancelHandle:handle];
//
//    [self runUntilDone];
//
//    STAssertTrue(self.cancelled, @"should have been cancelled");
//    STAssertNil(self.response, @"should have no response");
//    STAssertTrue([self.buffer length] == 0, @"should have no data");
//    STAssertNil(self.error, @"got error %@", self.error);
//
//    [handle release];
//
//    [multi shutdown];
//    
//    [multi release];
//
//}

@end
