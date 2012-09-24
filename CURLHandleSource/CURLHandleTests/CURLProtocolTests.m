//
//  CURLProtocolTests.m
//  CURLProtocolTests
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLProtocol.h"

#import <SenTestingKit/SenTestingKit.h>

@interface CURLProtocolTests : SenTestCase<NSURLConnectionDelegate>

@property (strong, nonatomic) NSMutableData* data;
@property (assign, atomic) BOOL exitRunLoop;
@property (strong, nonatomic) NSURLResponse* response;
@property (assign, nonatomic) BOOL sending;

@end

@implementation CURLProtocolTests

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    self.exitRunLoop = YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.response = response;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)dataIn
{
    NSMutableData* data = self.data;
    if (!data)
    {
        data = [NSMutableData dataWithCapacity:self.response.expectedContentLength];
        self.data = data;
    }

    [data appendData:dataIn];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    self.exitRunLoop = YES;
}


- (void)testSimpleDownload
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://raw.github.com/karelia/CurlHandle/master/DevNotes.txt"]];
    request.shouldUseCurlHandle = YES;

    NSURLConnection* connection = [NSURLConnection connectionWithRequest:request delegate:self];
    [connection start];
    
    STAssertNotNil(connection, @"failed to get connection for request %@", request);

    self.exitRunLoop = NO;
    while (!self.exitRunLoop)
    {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
    }

    STAssertNotNil(self.response, @"got no response");
    STAssertTrue([self.data length] > 0, @"got no data");

    NSError* error = nil;
    NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
    NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];
    NSString* receivedNotes = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
    STAssertTrue([receivedNotes isEqualToString:devNotes], @"received notes didn't match: was:\n%@\n\nshould have been:\n%@", receivedNotes, devNotes);
}

@end
