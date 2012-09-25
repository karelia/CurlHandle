//
//  CURLHandleTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLHandleBasedTest.h"
#import "NSURLRequest+CURLHandle.h"

@interface CURLHandleTests : CURLHandleBasedTest

@end

@implementation CURLHandleTests

- (void)testHTTPDownload
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


- (void)testFTPDownload
{
    NSURL* ftpRoot = [self ftpTestServer];
    NSURL* ftpDownload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"DevNotes.txt"];

    CURLHandle* handle = [[CURLHandle alloc] init];
    handle.delegate = self;

    NSError* error = nil;
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpDownload];

    BOOL ok = [handle loadRequest:request error:&error];
    STAssertTrue(ok, @"failed to load request, with error %@", error);

    [self checkDownloadedBufferWasCorrect];

    [handle release];
}

- (void)testFTPUpload
{
    NSURL* ftpRoot = [self ftpTestServer];
    NSURL* ftpUpload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"Upload.txt"];

    NSError* error = nil;
    NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
    NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];

    CURLHandle* handle = [[CURLHandle alloc] init];
    handle.delegate = self;

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpUpload];
    request.shouldUseCurlHandle = YES;
    [request curl_setCreateIntermediateDirectories:1];
    [request setHTTPBody:[devNotes dataUsingEncoding:NSUTF8StringEncoding]];

    BOOL ok = [handle loadRequest:request error:&error];
    STAssertTrue(ok, @"failed to load request, with error %@", error);

    STAssertTrue(self.sending, @"should have set sending flag");
    STAssertNil(self.error, @"got error %@", self.error);
    STAssertNil(self.response, @"got unexpected response %@", self.response);
    STAssertTrue([self.buffer length] == 0, @"got unexpected data %@", self.buffer);

    
}

@end
