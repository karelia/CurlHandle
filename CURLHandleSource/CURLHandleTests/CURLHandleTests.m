//
//  CURLHandleTests.m
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLHandleBasedTest.h"
#import "CURLMulti.h"

#import "NSURLRequest+CURLHandle.h"

#pragma mark - Globals

typedef enum
{
    TEST_SYNCHRONOUS,
    TEST_WITH_OWN_MULTI,
    TEST_WITH_SHARED_MULTI,

    TEST_MODE_COUNT
} TestMode;

static const NSUInteger kIterationsToPerform = TEST_MODE_COUNT;

// Each test will run kIterationsToPerform times, working its way through the modes in the TestMode enum.
// You can re-order the enums, and reduce the value of kIterationsToPerform if you only want to use some of these modes.
//
// In mode TEST_WITH_SHARED_MULTI  all the tests use the shared multi from [CURLMulti sharedInstance].
// Using the shared multi is potentially dubious because the state of the multi is retained across tests.
// However, it's also how things are in the real world.
// In mode TEST_WITH_OWN_MULTI a new multi is made at the start of each test, all test operations are done using it
// and it's then shutdown at the end of the test.
// In mode TEST_SYNCHRONOUS the old synchronous API is used.

#pragma mark - Test Class

@interface CURLHandleTests : CURLHandleBasedTest

@property (strong, nonatomic) CURLMulti* multi;
@property (assign, nonatomic) TestMode mode;

@end


@implementation CURLHandleTests

- (void)dealloc
{
    [_multi release];

    [super dealloc];
}

- (void)cleanup
{
    switch (self.mode)
    {
        case TEST_WITH_OWN_MULTI:
            [self.multi shutdown];
            break;

        default:
            break;
    }

    self.multi = nil;
    [super cleanup];
}

- (NSString*)nameForIteration:(NSUInteger)iteration
{
    NSString* iterationName;
    switch (iteration)
    {
        case TEST_SYNCHRONOUS:
            iterationName = @"Synchronous";
            break;

        case TEST_WITH_SHARED_MULTI:
            iterationName = @"Shared Multi";
            break;

        case TEST_WITH_OWN_MULTI:
            iterationName = @"Own Multi";
            break;

        default:
            iterationName = @"Invalid";
            break;
    }

    return iterationName;
}

- (void) beforeTestIteration:(NSUInteger)iteration selector:(SEL)testMethod
{
    STAssertTrue(iteration < TEST_MODE_COUNT, @"invalid iteration count %d", iteration);

    NSLog(@"\n\n************************************************************\nStarting %@ %@\n************************************************************\n\n", [self nameForIteration:iteration], [self name]);
    self.mode = (TestMode)iteration;
}

- (void)afterTestIteration:(NSUInteger)iteration selector:(SEL)testMethod
{
    [self cleanup];
    [self cleanupServer];
    NSLog(@"\n\n************************************************************\nDone %@ %@\n************************************************************\n\n", [self nameForIteration:iteration], [self name]);
}

- (NSUInteger) numberOfTestIterationsForTestWithSelector:(SEL)testMethod
{
    return kIterationsToPerform;
}

- (CURLHandle*)makeHandleWithRequest:(NSURLRequest*)request
{
    switch (self.mode)
    {
        case TEST_WITH_OWN_MULTI:
            if (!self.multi)
            {
                NSLog(@"Using custom multi");
                self.multi = [[[CURLMulti alloc] init] autorelease];
                [self.multi startup];
            }
            break;

        case TEST_SYNCHRONOUS:
        case TEST_WITH_SHARED_MULTI:
            self.multi = [CURLMulti sharedInstance];
            break;

        default:
            break;
    }

    CURLHandle* handle;
    if (self.mode == TEST_SYNCHRONOUS)
    {
        if ([self usingMockServer])
        {
            handle = nil;
            NSLog(@"Skipping test for synchronous iteration as we're using MockServer");
        }
        else
        {
            handle = [[CURLHandle alloc] init];
            [handle sendSynchronousRequest:request credential:nil delegate:self];
        }
    }
    else
    {
       handle = [[CURLHandle alloc] initWithRequest:request credential:nil delegate:self multi:self.multi];
    }
    
    return handle;
}

- (CURLHandle*)newDownloadWithRoot:(NSURL*)ftpRoot
{
    NSURL* ftpDownload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"TestContent.txt"];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpDownload];
    CURLHandle* handle = [self makeHandleWithRequest:request];

    return handle;
}

- (void)doFTPDownloadWithRoot:(NSURL*)ftpRoot
{
    CURLHandle* handle = [self newDownloadWithRoot:ftpRoot];
    if (handle)
    {
        if (self.mode != TEST_SYNCHRONOUS)
        {
            [self runUntilPaused];
        }

        STAssertTrue([self checkDownloadedBufferWasCorrect], @"download ok");
        
        [handle release];
    }
}

- (CURLHandle*)newUploadWithRoot:(NSURL*)ftpRoot
{
    NSURL* ftpUpload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"Upload.txt"];

    NSError* error = nil;
    NSURL* testNotesURL = [self testFileURL];
    NSString* testNotes = [NSString stringWithContentsOfURL:testNotesURL encoding:NSUTF8StringEncoding error:&error];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpUpload];
    request.shouldUseCurlHandle = YES;
    [request curl_setCreateIntermediateDirectories:1];
    [request setHTTPBody:[testNotes dataUsingEncoding:NSUTF8StringEncoding]];
    CURLHandle* handle = [self makeHandleWithRequest:request];

    return handle;
}

- (void)doFTPUploadWithRoot:(NSURL*)ftpRoot
{
    [self.buffer setLength:0];
    self.response = nil;

    CURLHandle* handle = [self newUploadWithRoot:ftpRoot];
    if (handle)
    {
        if (self.mode != TEST_SYNCHRONOUS)
        {
            [self runUntilPaused];
        }

        STAssertTrue(self.sending, @"should have set sending flag");
        STAssertNil(self.error, @"got error %@", self.error);

        NSHTTPURLResponse* response = (NSHTTPURLResponse*)self.response;
        STAssertTrue([response respondsToSelector:@selector(statusCode)], @"got response of class %@", [response class]);
        STAssertEquals([response statusCode], (NSInteger) 226, @"got unexpected code %ld", [response statusCode]);
        STAssertTrue([self.buffer length] == 0, @"got unexpected data %@", [[[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding] autorelease]);
        
        [handle release];
    }
}

#pragma mark - Tests

- (void)testVersion
{
    NSString* version = [CURLHandle curlVersion];
    NSLog(@"curl version %@", version);
    STAssertTrue([version isEqualToString:@"libcurl/7.28.2-DEV SecureTransport zlib/1.2.5 c-ares/1.9.0-DEV libssh2/1.4.3_DEV"], @"version was \n\n%@\n\n", version);
}

- (void)testHTTPDownload
{
    NSURLRequest* request = [NSURLRequest requestWithURL:[self testFileRemoteURL]];
    CURLHandle* handle = [self makeHandleWithRequest:request];
    if (handle)
    {
        if (self.mode != TEST_SYNCHRONOUS)
        {
            [self runUntilPaused];
        }

        STAssertTrue([self checkDownloadedBufferWasCorrect], @"download ok");
        
        [handle release];
    }
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
        [self doFTPUploadWithRoot:ftpRoot];
        [self doFTPUploadWithRoot:ftpRoot];
    }
}

- (void)testFTPThrashInParallel
{
    // do a quick sequence of stuff

    if (self.mode != TEST_SYNCHRONOUS)
    {
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
            while (self.error == nil && (self.finishedCount < count))
            {
                [self runUntilPaused];
            }

            for (CURLHandle* handle in handles)
            {
                [handle release];
            }
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
        if (handle)
        {
            if (self.mode != TEST_SYNCHRONOUS)
            {
                [self runUntilPaused];
            }

            STAssertNil(self.error, @"got error %@", self.error);
            STAssertNotNil(self.response, @"got unexpected response %@", self.response);
            STAssertTrue([self.buffer length] == 0, @"got unexpected data: '%@'", [[[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding] autorelease]);
            
            [handle release];
        }
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
        if (handle)
        {
            if (self.mode != TEST_SYNCHRONOUS)
            {
                [self runUntilPaused];
            }

            STAssertNil(self.error, @"got error %@", self.error);
            STAssertNotNil(self.response, @"got unexpected response %@", self.response);

            NSString* reply = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
            BOOL result = [reply isEqualToString:@""];
            STAssertTrue(result, @"reply didn't match: was:\n'%@'\n\nshould have been:\n'%@'", reply, @"");
            [reply release];
            
            [handle release];
        }
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
        if (handle)
        {
            if (self.mode != TEST_SYNCHRONOUS)
            {
                [self runUntilPaused];
            }

            if (self.error)
            {
                NSInteger curlResponse = [[[self.error userInfo] objectForKey:[NSNumber numberWithInt:CURLINFO_RESPONSE_CODE]] integerValue];
                STAssertTrue((self.error.code == 21) && (curlResponse == 550), @"got unexpected error %@", self.error);
            }
            else
            {
                NSHTTPURLResponse* response = (NSHTTPURLResponse*)self.response;
                STAssertNotNil(response, @"expecting response");
                STAssertTrue(response.statusCode == 257, @"unexpected response code %ld", response.statusCode);
            }

            STAssertTrue([self.buffer length] == 0, @"got unexpected data: '%@'", [[[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding] autorelease]);
            
            [handle release];
        }
    }
}

@end
