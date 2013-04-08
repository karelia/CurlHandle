//
//  CURLMultiTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLMulti.h"
#import "CURLHandleBasedTest.h"
#import "CURLHandle+TestingSupport.h"

#import "NSURLRequest+CURLHandle.h"
#import "KMSServer.h"


@interface CURLMultiTests : CURLHandleBasedTest

@property (assign, nonatomic) BOOL pauseOnResponse;
@property (assign, nonatomic) BOOL finished;
@end

@implementation CURLMultiTests


- (void)handle:(CURLHandle *)handle didReceiveResponse:(NSURLResponse *)response
{
    if (self.pauseOnResponse)
    {
        [self pause];
    }
    [super handle:handle didReceiveResponse:response];
}

- (void)handleDidFinish:(CURLHandle *)handle
{
    self.finished = YES;
    [super handleDidFinish:handle];
}

#pragma mark - Tests

- (void)testStartupShutdown
{
    CURLMulti* multi = [[CURLMulti alloc] init];

    [multi startup];

    [multi shutdown];

    [multi release];
}

- (void)testHTTPDownload
{
    CURLMulti* multi = [[CURLMulti alloc] init];

    [multi startup];

    NSURLRequest* request = [NSURLRequest requestWithURL:[self testFileRemoteURL]];
    CURLHandle* handle = [[CURLHandle alloc] initWithRequest:request credential:nil delegate:self multi:multi];

    [self runUntilPaused];

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
    if (ftpRoot)
    {
        NSURL* ftpDownload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"TestContent.txt"];

        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpDownload];
        CURLHandle* handle = [[CURLHandle alloc] initWithRequest:request credential:nil delegate:self multi:multi];

        [self runUntilPaused];

        [self checkDownloadedBufferWasCorrect];
        
        [handle release];
    }

    [multi shutdown];

    [multi release];
}

- (void)testFTPUpload
{
    CURLMulti* multi = [[CURLMulti alloc] init];

    [multi startup];
    
    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        NSURL* ftpUpload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"Upload.txt"];

        NSError* error = nil;
        NSURL* devNotesURL = [self testFileURL];
        NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];

        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpUpload];
        request.shouldUseCurlHandle = YES;
        [request curl_setCreateIntermediateDirectories:1];
        [request setHTTPBody:[devNotes dataUsingEncoding:NSUTF8StringEncoding]];
        CURLHandle* handle = [[CURLHandle alloc] initWithRequest:request credential:nil delegate:self multi:multi];

        [self runUntilPaused];

        STAssertTrue(self.sending, @"should have set sending flag");
        STAssertNil(self.error, @"got error %@", self.error);
        STAssertNotNil(self.response, @"expected response");
        STAssertTrue([self.buffer length] == 0, @"got unexpected data %@", self.buffer);
        
        [handle release];
    }

    [multi shutdown];

    [multi release];

}

- (void)testCancelling
{
    self.pauseOnResponse = YES;

    CURLMulti* multi = [[CURLMulti alloc] init];

    [multi startup];

    NSURL* largeFile = [NSURL URLWithString:@"https://github.com/karelia/CurlHandle/archive/master.zip"];
    NSURLRequest* request = [NSURLRequest requestWithURL:largeFile];
    CURLHandle* handle = [[CURLHandle alloc] initWithRequest:request credential:nil delegate:self multi:multi];

    // CURL seems to die horribly if we create and shutdown the multi without actually adding at least one easy handle to it - so wait until
    // we've at least received the response
    
    [self runUntilPaused];

    [handle cancel];

    STAssertTrue([handle isCancelled], @"should have been cancelled");

    // wait until the multi actually gets round to removing the handle
    while ([handle handledByMulti])
    {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
    }

    STAssertFalse(self.finished, @"shouldn't have finished by the time we get here");
    
    [handle release];

    [multi shutdown];
    
    [multi release];
}


@end
