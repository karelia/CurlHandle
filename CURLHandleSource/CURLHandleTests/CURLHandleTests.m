//
//  CURLHandleTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

// Each test here is run twice.
// - Once, using the default [CURLMulti sharedInstance] multi: this is potentially dubious because the state of the multi is retained across tests. However,
//   it's also how things are in the real world.
// - Once, using a custom CURLMulti instance for each test: this makes each test more isolated, although libcurl is probably still caching things.

#import "CURLHandleBasedTest.h"
#import "CURLMulti.h"

#import "NSURLRequest+CURLHandle.h"

@interface CURLHandle(TestingOnly)
- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential delegate:(id <CURLHandleDelegate>)delegate multi:(CURLMulti*)multi;
@end

@interface CURLHandleTests : CURLHandleBasedTest

@property (strong, nonatomic) CURLMulti* multi;
@property (assign, nonatomic) BOOL useCustomMulti;

@end

@implementation CURLHandleTests

- (void)dealloc
{
    [_multi release];

    [super dealloc];
}

- (void)cleanup
{
    if (self.useCustomMulti)
    {
        [self.multi shutdown];
        self.multi = nil;
    }

    [super cleanup];
}

static NSUInteger gIteration = 0;
static const NSUInteger kIterationToUseCustomMulti = 1;

- (void) beforeTestIteration:(NSUInteger)iteration selector:(SEL)testMethod
{
    NSLog(@"\n\nIteration #%ld\n\n", iteration);

    self.useCustomMulti = iteration == kIterationToUseCustomMulti;
}

- (void)afterTestIteration:(NSUInteger)iteration selector:(SEL)testMethod
{
    [self cleanup];
    [self cleanupServer];
    gIteration++;
}

- (NSUInteger) numberOfTestIterationsForTestWithSelector:(SEL)testMethod
{
    return 1;
}

- (NSString*)name
{
    NSString* result = [super name];
    if (gIteration == kIterationToUseCustomMulti)
    {
        NSRange range = [result rangeOfString:@" "];
        result = [NSString stringWithFormat:@"%@WithCustomMulti %@", [result substringToIndex:range.location], [result substringFromIndex:range.location + 1]];
    }

    return result;
}

- (CURLHandle*)makeHandleWithRequest:(NSURLRequest*)request
{
    if (self.useCustomMulti)
    {
        NSLog(@"Using custom multi");
        self.multi = [[[CURLMulti alloc] init] autorelease];
        [self.multi startup];
    }
    else
    {
        NSLog(@"Using default shared multi");
        self.multi = [CURLMulti sharedInstance];
    }

    CURLHandle* handle = [[CURLHandle alloc] initWithRequest:request credential:nil delegate:self multi:self.multi];

    return handle;
}

- (CURLHandle*)newDownloadWithRoot:(NSURL*)ftpRoot
{
    NSURL* ftpDownload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"DevNotes.txt"];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpDownload];
    CURLHandle* handle = [self makeHandleWithRequest:request];

    return handle;
}

- (void)doFTPDownloadWithRoot:(NSURL*)ftpRoot
{
    CURLHandle* handle = [self newDownloadWithRoot:ftpRoot];

    [self runUntilPaused];

    STAssertTrue([self checkDownloadedBufferWasCorrect], @"download ok");

    [handle release];
}

- (CURLHandle*)newUploadWithRoot:(NSURL*)ftpRoot
{
    NSURL* ftpUpload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"Upload.txt"];

    NSError* error = nil;
    NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
    NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpUpload];
    request.shouldUseCurlHandle = YES;
    [request curl_setCreateIntermediateDirectories:1];
    [request setHTTPBody:[devNotes dataUsingEncoding:NSUTF8StringEncoding]];
    CURLHandle* handle = [self makeHandleWithRequest:request];

    return handle;
}

- (void)doFTPUploadWithRoot:(NSURL*)ftpRoot
{
    [self.buffer setLength:0];
    self.response = nil;

    CURLHandle* handle = [self newUploadWithRoot:ftpRoot];

    [self runUntilPaused];

    STAssertTrue(self.sending, @"should have set sending flag");
    STAssertNil(self.error, @"got error %@", self.error);

    NSHTTPURLResponse* response = (NSHTTPURLResponse*)self.response;
    STAssertTrue([response isMemberOfClass:[NSHTTPURLResponse class]], @"got response of class %@", [NSHTTPURLResponse class]);
    STAssertEquals([response statusCode], (NSInteger) 226, @"got unexpected code %ld", [response statusCode]);
    STAssertTrue([self.buffer length] == 0, @"got unexpected data %@", [[[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding] autorelease]);

    [handle release];
}

- (void)testVersion
{
    CURLHandleLog(@"curl version %@", [CURLHandle curlVersion]);
}

- (void)testHTTPDownload
{
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];
    CURLHandle* handle = [self makeHandleWithRequest:request];

    [self runUntilPaused];

    STAssertTrue([self checkDownloadedBufferWasCorrect], @"download ok");

    [handle release];
}


- (void)testFTPDownload
{
    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        [self doFTPDownloadWithRoot:ftpRoot];
    }
}

- (void)testFTPUpload
{
    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        [self doFTPUploadWithRoot:ftpRoot];
    }
}

- (void)testFTPThrashInSeries
{
    // do a quick sequence of stuff

    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        [self doFTPUploadWithRoot:ftpRoot];
        //[self doFTPDownloadWithRoot:ftpRoot];
        [self doFTPUploadWithRoot:ftpRoot];
        //[self doFTPDownloadWithRoot:ftpRoot];
    }
}

- (void)testFTPThrashInParallel
{
    // do a quick sequence of stuff

    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        NSArray* handles = @[
                             [self newDownloadWithRoot:ftpRoot],
                             [self newUploadWithRoot:ftpRoot],
                             [self newDownloadWithRoot:ftpRoot],
                             [self newUploadWithRoot:ftpRoot],
                             [self newDownloadWithRoot:ftpRoot],
                             [self newUploadWithRoot:ftpRoot]
                             ];

        NSUInteger count = [handles count];
        while (self.finishedCount < count)
        {
            [self runUntilPaused];
        }

        for (CURLHandle* handle in handles)
        {
            [handle release];
        }
    }
}

- (void)testFTPUploadThenDelete
{
    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        NSURL* ftpUploadFolder = [ftpRoot URLByAppendingPathComponent:@"CURLHandleTests/"];
        [self doFTPUploadWithRoot:ftpRoot];

        self.response = nil;
        [self.buffer setLength:0];

        // Navigate to the directory
        // @"HEAD" => CURLOPT_NOBODY, which stops libcurl from trying to list the directory's contents
        // If the connection is already at that directory then curl wisely does nothing
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:ftpUploadFolder];
        [request setHTTPMethod:@"HEAD"];
        [request curl_setCreateIntermediateDirectories:YES];
        [request curl_setPreTransferCommands:@[@"DELE Upload.txt"]];

        CURLHandle* handle = [self makeHandleWithRequest:request];

        [self runUntilPaused];

        STAssertNil(self.error, @"got error %@", self.error);
        STAssertNotNil(self.response, @"got unexpected response %@", self.response);
        STAssertTrue([self.buffer length] == 0, @"got unexpected data: '%@'", [[[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding] autorelease]);

        [handle release];


    }
}

- (void)testFTPUploadThenChangePermissions
{
    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        NSURL* ftpUploadFolder = [ftpRoot URLByAppendingPathComponent:@"CURLHandleTests/"];
        [self doFTPUploadWithRoot:ftpRoot];

        self.response = nil;
        [self.buffer setLength:0];

        // Navigate to the directory
        // @"HEAD" => CURLOPT_NOBODY, which stops libcurl from trying to list the directory's contents
        // If the connection is already at that directory then curl wisely does nothing
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:ftpUploadFolder];
        [request setHTTPMethod:@"HEAD"];
        [request curl_setCreateIntermediateDirectories:YES];
        [request curl_setPreTransferCommands:@[@"SITE CHMOD 0777 Upload.txt"]];

        CURLHandle* handle = [self makeHandleWithRequest:request];

        [self runUntilPaused];

        STAssertNil(self.error, @"got error %@", self.error);
        STAssertNotNil(self.response, @"got unexpected response %@", self.response);

        NSString* reply = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
        BOOL result = [reply isEqualToString:@""];
        STAssertTrue(result, @"reply didn't match: was:\n'%@'\n\nshould have been:\n'%@'", reply, @"");
        [reply release];
        
        [handle release];
        
        
    }
}

- (void)testFTPMakeDirectory
{
    NSURL* ftpRoot = [self ftpTestServer];
    if (ftpRoot)
    {
        NSURL* ftpDirectory = [ftpRoot URLByAppendingPathComponent:@"CURLHandleTests/"];

        // Navigate to the directory
        // @"HEAD" => CURLOPT_NOBODY, which stops libcurl from trying to list the directory's contents
        // If the connection is already at that directory then curl wisely does nothing
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:ftpDirectory];
        [request setHTTPMethod:@"HEAD"];
        [request curl_setCreateIntermediateDirectories:YES];
        [request curl_setPreTransferCommands:@[@"MKD Subdirectory"]];

        CURLHandle* handle = [self makeHandleWithRequest:request];

        [self runUntilPaused];

        STAssertTrue((self.error == nil) || ((self.error.code == 21) && ([self.error.localizedDescription isEqualToString:@"QUOT command failed with 550"])), @"got unexpected error %@", self.error);
        STAssertTrue((self.error != nil) || (self.response == nil), @"got unexpected response %@", self.response);
        STAssertTrue([self.buffer length] == 0, @"got unexpected data: '%@'", [[[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding] autorelease]);

        [handle release];
    }
}

@end
