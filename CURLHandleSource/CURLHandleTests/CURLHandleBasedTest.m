//
//  CURLHandleBasedTest
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLHandleBasedTest.h"
#import "KMSServer.h"

@implementation CURLHandleBasedTest

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data
{
    NSMutableData* buffer = self.buffer;
    if (!buffer)
    {
        buffer = [NSMutableData dataWithCapacity:self.expected];
        self.buffer = buffer;
    }

    [buffer appendData:data];
}

- (void)handle:(CURLHandle *)handle didReceiveResponse:(NSURLResponse *)response
{
    self.response = response;
    if (response.expectedContentLength > 0)
    {
        self.expected = response.expectedContentLength;
    }
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    self.sending = YES;
    if (bytesWritten == 0)
    {
        NSLog(@"test: upload done");
    }
}

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type
{
    NSString* typeName = [handle nameForType:type];
    if (!self.transcript)
    {
        self.transcript = [NSMutableString stringWithString:@""];
    }

    [self.transcript appendFormat:@"%@: %@", typeName, string];
}

- (void)handleDidFinish:(CURLHandle *)handle
{
    NSLog(@"test: handle %@ finished", handle);
    self.finishedCount++;
    [self pause];
}

- (void)handle:(CURLHandle*)handle didFailWithError:(NSError *)error
{
    NSLog(@"test: handle failed with error %@", error);
    self.error = error;
    [self pause];
}

- (void)pause
{
    NSLog(@"test: pause requested");
    if (self.server)
    {
        [self.server pause];
    }
    else
    {
        self.exitRunLoop = YES;
    }
}

- (void)runUntilPaused
{
    if (self.server)
    {
        [self.server runUntilPaused];
    }
    else
    {
        while (!self.exitRunLoop)
        {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
        }
        self.exitRunLoop = NO;
    }
    NSLog(@"test: paused");
}

- (void)stopServer
{
    if (self.server)
    {
        [self.server stop];
        while (self.server.state != KMSStopped)
        {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
        }
    }
}

- (BOOL)checkDownloadedBufferWasCorrect
{
    STAssertNotNil(self.response, @"got no response");
    STAssertTrue([self.buffer length] > 0, @"got no data, expected %ld", self.expected);
    STAssertNil(self.error, @"got error %@", self.error);

    NSError* error = nil;
    NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
    NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];
    NSString* receivedNotes = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];

    BOOL result = [receivedNotes isEqualToString:devNotes];
    STAssertTrue(result, @"received notes didn't match: was:\n'%@'\n\nshould have been:\n'%@'", receivedNotes, devNotes);

    // clear the buffer
    [self.buffer setLength:0];
    
    return result;
}

- (NSURL*)ftpTestServer
{
    NSURL* result = nil;
    NSString* ftpTest = [[NSUserDefaults standardUserDefaults] objectForKey:@"CURLHandleFTPTestURL"];
    if ([ftpTest isEqualToString:@"MockServer"])
    {
        [self setupServerWithResponseFileNamed:@"ftp"];

        NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
        self.server.data = [NSData dataWithContentsOfURL:devNotesURL];

        result = [self URLForPath:@"/"];
    }
    else
    {
        STAssertNotNil(ftpTest, @"need to set a test server address using defaults, e.g: defaults write otest CURLHandleFTPTestURL \"ftp://user:password@ftp.test.com\"");
        result = [NSURL URLWithString:ftpTest];
    }

    return result;
}

- (void)cleanup
{
    if (self.transcript)
    {
        NSLog(@"Transcript:\n\n%@", self.transcript);
    }
    else
    {
        NSLog(@"No transcript.");
    }

    self.buffer = nil;
    self.transcript = nil;
    self.response = nil;
    self.error = nil;
}

- (void)tearDown
{
    [self cleanup];
    [super tearDown];
}

@end
