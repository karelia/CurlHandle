//
//  CURLHandleTests.m
//  CURLHandleTests
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLHandle.h"

#import <SenTestingKit/SenTestingKit.h>

@interface CURLHandleTests : SenTestCase<CURLHandleDelegate>

@property (strong, nonatomic) NSData* data;
@property (strong, nonatomic) NSURLResponse* response;
@property (assign, nonatomic) BOOL sending;

@end

@implementation CURLHandleTests

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data
{
    self.data = data;
}

- (void)handle:(CURLHandle *)handle didReceiveResponse:(NSURLResponse *)response
{
    self.response = response;
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    self.sending = YES;
}

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type
{
    CURLHandleLog(@"got debug info: %@ type:%d", string, type);
}


- (void)testSimpleDownload
{
    CURLHandle* handle = [[CURLHandle alloc] init];
    handle.delegate = self;

    NSError* error = nil;
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];

    BOOL ok = [handle loadRequest:request error:&error];
    STAssertTrue(ok, @"failed to load request, with error %@", error);

    STAssertNotNil(self.response, @"got no response");
    STAssertTrue([self.data length] > 0, @"got no data");

    NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
    NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];
    NSString* receivedNotes = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
    STAssertTrue([receivedNotes isEqualToString:devNotes], @"received notes didn't match: was:\n%@\n\nshould have been:\n%@", receivedNotes, devNotes);

    [handle release];
}

@end
