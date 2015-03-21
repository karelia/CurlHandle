//
//  CURLTransferTests.m
//  CURLHandle
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import "CURLHandleBasedTest.h"
#import "CURLTransfer+TestingSupport.h"
#import "CURLTransferStack.h"

#import "CURLRequest.h"

#pragma mark - Globals

typedef enum
{
    TEST_SYNCHRONOUS,
    TEST_WITH_OWN_MULTI,
    TEST_WITH_SHARED_MULTI,

    TEST_MODE_COUNT
} TestMode;


// In mode TEST_WITH_SHARED_MULTI  all the tests use the shared multi from [CURLMulti sharedInstance].
// Using the shared multi is potentially dubious because the state of the multi is retained across tests.
// However, it's also how things are in the real world.
// In mode TEST_WITH_OWN_MULTI a new multi is made at the start of each test, all test operations are done using it
// and it's then shutdown at the end of the test.
// In mode TEST_SYNCHRONOUS the old synchronous API is used.

#pragma mark - Test Class

@interface CURLTransferTests : CURLHandleBasedTest

@property (strong, nonatomic) CURLTransferStack* multi;
@property (assign, nonatomic) TestMode mode;

@end

static TestMode gModeToUse;

@implementation CURLTransferTests

+ (id) defaultTestSuite
{
    NSArray* modes = @[@(TEST_WITH_SHARED_MULTI), @(TEST_SYNCHRONOUS)];
    // Not testing TEST_WITH_OWN_MULTI as tends to hang trying to clean up after mock server

    XCTestSuite* result = [[XCTestSuite alloc] initWithName:[NSString stringWithFormat:@"%@Collection", NSStringFromClass(self)]];
    for (NSNumber* mode in modes)
    {
        // in order to re-use the default SenTest mechanism for building up a suite of tests, we set some global variables
        // to indicate the test configuration we want, then call on to the defaultTestSuite to get a set of tests using that configuration.
        gModeToUse = (TestMode)[mode unsignedIntegerValue];
        XCTestSuite* suite = [[XCTestSuite alloc] initWithName:[NSString stringWithFormat:@"%@Using%@", NSStringFromClass(self), [CURLTransferTests nameForMode:gModeToUse]]];
        [suite addTest:[super defaultTestSuite]];
        [result addTest:suite];
        [suite release];
    }

    return [result autorelease];
}

- (id)initWithInvocation:(NSInvocation *)anInvocation
{
    if ((self = [super initWithInvocation:anInvocation]) != nil)
    {
        self.mode = gModeToUse;
    }

    return self;
}

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

+ (NSString*)nameForMode:(TestMode)mode
{
    NSString* name;
    switch (mode)
    {
        case TEST_SYNCHRONOUS:
            name = @"Synchronous";
            break;

        case TEST_WITH_SHARED_MULTI:
            name = @"Shared Multi";
            break;

        case TEST_WITH_OWN_MULTI:
            name = @"Own Multi";
            break;

        default:
            name = @"Invalid";
            break;
    }

    return name;
}

- (CURLTransfer*)newHandleWithRequest:(NSURLRequest*)request
{
    switch (self.mode)
    {
        case TEST_WITH_OWN_MULTI:
            if (!self.multi)
            {
                NSLog(@"Using custom multi");
                self.multi = [[[CURLTransferStack alloc] init] autorelease];
            }
            break;

        case TEST_SYNCHRONOUS:
        case TEST_WITH_SHARED_MULTI:
            self.multi = [CURLTransferStack sharedInstance];
            break;

        default:
            break;
    }

    CURLTransfer* transfer;
    if (self.mode == TEST_SYNCHRONOUS)
    {
        if ([self usingMockServer])
        {
            transfer = nil;
            NSLog(@"Skipping test for synchronous iteration as we're using MockServer");
        }
        else
        {
            transfer = [[CURLTransfer alloc] init];
            [transfer sendSynchronousRequest:request credential:nil delegate:self];
        }
    }
    else
    {
       transfer = [[CURLTransfer alloc] initWithRequest:request credential:nil delegate:self delegateQueue:[NSOperationQueue mainQueue] multi:self.multi];
    }
    
    return transfer;
}

- (CURLTransfer*)newDownloadWithRoot:(NSURL*)ftpRoot
{
    NSURL* ftpDownload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"TestContent.txt"];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpDownload];
    CURLTransfer* transfer = [self newHandleWithRequest:request];

    return transfer;
}

- (void)doFTPDownloadWithRoot:(NSURL*)ftpRoot
{
    CURLTransfer* transfer = [self newDownloadWithRoot:ftpRoot];
    if (transfer)
    {
        if (self.mode != TEST_SYNCHRONOUS)
        {
            [self runUntilPaused];
        }

        XCTAssertTrue([self checkDownloadedBufferWasCorrect], @"download ok");
        
        [transfer release];
    }
}

- (CURLTransfer*)newUploadWithRoot:(NSURL*)ftpRoot
{
    NSURL* ftpUpload = [[ftpRoot URLByAppendingPathComponent:@"CURLHandleTests"] URLByAppendingPathComponent:@"Upload.txt"];

    NSError* error = nil;
    NSURL* testNotesURL = [self testFileURL];
    NSString* testNotes = [NSString stringWithContentsOfURL:testNotesURL encoding:NSUTF8StringEncoding error:&error];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:ftpUpload];
    [request curl_setCreateIntermediateDirectories:1];
    [request setHTTPBody:[testNotes dataUsingEncoding:NSUTF8StringEncoding]];
    CURLTransfer* transfer = [self newHandleWithRequest:request];

    return transfer;
}

- (void)doFTPUploadWithRoot:(NSURL*)ftpRoot
{
    [self.buffer setLength:0];
    self.response = nil;

    CURLTransfer* transfer = [self newUploadWithRoot:ftpRoot];
    if (transfer)
    {
        if (self.mode != TEST_SYNCHRONOUS)
        {
            [self runUntilPaused];
        }

        XCTAssertTrue(self.sending, @"should have set sending flag");
        XCTAssertNil(self.error, @"got error %@", self.error);

        NSHTTPURLResponse* response = (NSHTTPURLResponse*)self.response;
        XCTAssertTrue([response respondsToSelector:@selector(statusCode)], @"got response of class %@", [response class]);
        XCTAssertEqual([response statusCode], (NSInteger) 226, @"got unexpected code %ld", [response statusCode]);
        XCTAssertTrue([self.buffer length] == 0, @"got unexpected data %@", [[[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding] autorelease]);
        
        [transfer release];
    }
}

#pragma mark - Tests

- (void)testVersion
{
    NSString* version = [CURLTransfer curlVersion];
    NSLog(@"curl version %@", version);
    XCTAssertTrue([version isEqualToString:@"libcurl/7.31.0-DEV SecureTransport zlib/1.2.5 c-ares/1.10.0-DEV libssh2/1.4.3_DEV"], @"version was \n\n%@\n\n", version);
}

- (void)testHTTPDownload
{
    NSURLRequest* request = [NSURLRequest requestWithURL:[self testFileRemoteURL]];
    CURLTransfer* transfer = [self newHandleWithRequest:request];
    if (transfer)
    {
        if (self.mode != TEST_SYNCHRONOUS)
        {
            [self runUntilPaused];
        }

        XCTAssertTrue([self checkDownloadedBufferWasCorrect], @"download ok");
        
        [transfer release];
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
        [self doFTPDownloadWithRoot:ftpRoot];
        [self doFTPUploadWithRoot:ftpRoot];
        [self doFTPDownloadWithRoot:ftpRoot];
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
                                 [[self newDownloadWithRoot:ftpRoot] autorelease],
                                 [[self newUploadWithRoot:ftpRoot] autorelease],
                                 [[self newDownloadWithRoot:ftpRoot] autorelease],
                                 [[self newUploadWithRoot:ftpRoot] autorelease],
                                 [[self newDownloadWithRoot:ftpRoot] autorelease],
                                 [[self newUploadWithRoot:ftpRoot] autorelease]
                                 ];

            NSUInteger count = [handles count];
            while (self.error == nil && (self.finishedCount < count))
            {
                NSLog(@"%ld handles finished", self.finishedCount);
                [self runUntilPaused];
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

        CURLTransfer* transfer = [self newHandleWithRequest:request];
        if (transfer)
        {
            if (self.mode != TEST_SYNCHRONOUS)
            {
                [self runUntilPaused];
            }

            XCTAssertNil(self.error, @"got error %@", self.error);
            XCTAssertNotNil(self.response, @"got unexpected response %@", self.response);
            XCTAssertTrue([self.buffer length] == 0, @"got unexpected data: '%@'", [[[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding] autorelease]);
            
            [transfer release];
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

        CURLTransfer* transfer = [self newHandleWithRequest:request];
        if (transfer)
        {
            if (self.mode != TEST_SYNCHRONOUS)
            {
                [self runUntilPaused];
            }

            XCTAssertNil(self.error, @"got error %@", self.error);
            XCTAssertNotNil(self.response, @"got unexpected response %@", self.response);

            NSString* reply = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
            BOOL result = [reply isEqualToString:@""];
            XCTAssertTrue(result, @"reply didn't match: was:\n'%@'\n\nshould have been:\n'%@'", reply, @"");
            [reply release];
            
            [transfer release];
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

        CURLTransfer* transfer = [self newHandleWithRequest:request];
        if (transfer)
        {
            if (self.mode != TEST_SYNCHRONOUS)
            {
                [self runUntilPaused];
            }

            if (self.error)
            {
                NSInteger curlResponse = [[[self.error userInfo] objectForKey:[NSNumber numberWithInt:CURLINFO_RESPONSE_CODE]] integerValue];
                XCTAssertTrue((self.error.code == 21) && (curlResponse == 550), @"got unexpected error %@", self.error);
            }
            else
            {
                NSHTTPURLResponse* response = (NSHTTPURLResponse*)self.response;
                XCTAssertNotNil(response, @"expecting response");
                XCTAssertTrue(response.statusCode == 257, @"unexpected response code %ld", response.statusCode);
            }

            XCTAssertTrue([self.buffer length] == 0, @"got unexpected data: '%@'", [[[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding] autorelease]);
            
            [transfer release];
        }
    }
}

@end
