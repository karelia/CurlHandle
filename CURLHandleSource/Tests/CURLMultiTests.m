//
//  CURLMultiTests.m
//  CURLHandle
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import "CURLMultiHandle.h"
#import "CURLHandleBasedTest.h"
#import "CURLTransfer+TestingSupport.h"

#import "CURLRequest.h"
#import "KMSServer.h"


@interface CURLMultiTests : CURLHandleBasedTest

@property (assign, nonatomic) BOOL pauseOnResponse;
@property (assign, nonatomic) BOOL finished;
@end

@implementation CURLMultiTests


- (void)transfer:(CURLTransfer *)transfer didReceiveResponse:(NSURLResponse *)response
{
    if (self.pauseOnResponse)
    {
        [self pause];
    }
    [super transfer:transfer didReceiveResponse:response];
}

- (void)transfer:(CURLTransfer *)transfer didCompleteWithError:(NSError *)error;
{
    if (!error) self.finished = YES;
    [super transfer:transfer didCompleteWithError:error];
}

#pragma mark - Tests

- (void)testStartupShutdown
{
    CURLMultiHandle* multi = [[CURLMultiHandle alloc] init];

    [multi startup];

    [multi shutdown];

    [multi release];
}

- (void)testHTTPDownload
{
    CURLMultiHandle* multi = [[CURLMultiHandle alloc] init];

    [multi startup];

    NSURLRequest* request = [NSURLRequest requestWithURL:[self testFileRemoteURL]];
    CURLTransfer* transfer = [[CURLTransfer alloc] initWithRequest:request credential:nil delegate:self delegateQueue:[NSOperationQueue mainQueue] multi:multi];

    [self runUntilPaused];

    [self checkDownloadedBufferWasCorrect];

    [transfer release];

    [multi shutdown];

    [multi release];

}

- (void)testFTPDownload
{
    CURLMultiHandle* multi = [[CURLMultiHandle alloc] init];

    [multi startup];
    
    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        NSURL* ftpDownload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"TestContent.txt"];

        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpDownload];
        CURLTransfer* transfer = [[CURLTransfer alloc] initWithRequest:request credential:nil delegate:self delegateQueue:[NSOperationQueue mainQueue] multi:multi];

        [self runUntilPaused];

        [self checkDownloadedBufferWasCorrect];
        
        [transfer release];
    }

    [multi shutdown];

    [multi release];
}

- (void)testFTPUpload
{
    CURLMultiHandle* multi = [[CURLMultiHandle alloc] init];

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
        CURLTransfer* transfer = [[CURLTransfer alloc] initWithRequest:request credential:nil delegate:self delegateQueue:[NSOperationQueue mainQueue] multi:multi];

        [self runUntilPaused];

        STAssertTrue(self.sending, @"should have set sending flag");
        STAssertNil(self.error, @"got error %@", self.error);
        STAssertNotNil(self.response, @"expected response");
        STAssertTrue([self.buffer length] == 0, @"got unexpected data %@", self.buffer);
        
        [transfer release];
    }

    [multi shutdown];

    [multi release];

}

- (void)testCancelling
{
    self.pauseOnResponse = YES;

    CURLMultiHandle* multi = [[CURLMultiHandle alloc] init];

    [multi startup];

    NSURL* largeFile = [NSURL URLWithString:@"https://github.com/karelia/CurlHandle/archive/master.zip"];
    NSURLRequest* request = [NSURLRequest requestWithURL:largeFile];
    CURLTransfer* transfer = [[CURLTransfer alloc] initWithRequest:request credential:nil delegate:self delegateQueue:[NSOperationQueue mainQueue] multi:multi];

    // CURL seems to die horribly if we create and shutdown the multi without actually adding at least one easy transfer to it - so wait until
    // we've at least received the response
    
    [self runUntilPaused];

    [transfer cancel];

    STAssertTrue(transfer.state >= CURLTransferStateCanceling, @"should have been cancelled");

    // wait until the multi actually gets round to removing the transfer
    while (transfer.state != CURLTransferStateCompleted)
    {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
    }

    STAssertFalse(self.finished, @"shouldn't have finished by the time we get here");
    
    [transfer release];

    [multi shutdown];
    
    [multi release];
}


@end
