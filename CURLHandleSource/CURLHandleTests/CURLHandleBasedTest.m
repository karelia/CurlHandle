//
//  CURLHandleBasedTest
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLHandleBasedTest.h"
#import "CURLRunLoopSource.h"

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

    self.exitRunLoop = [buffer length] == self.expected;
}

- (void)handle:(CURLHandle *)handle didReceiveResponse:(NSURLResponse *)response
{
    self.response = response;
    self.expected = response.expectedContentLength;
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    self.sending = YES;
}

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type
{
    CURLHandleLog(@"got debug info: %@ type:%d", string, type);
}

- (void)runUntilDone
{
    self.exitRunLoop = NO;
    while (!self.exitRunLoop)
    {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate date]];
    }
}

- (void)checkDownloadedBufferWasCorrect
{
    STAssertNotNil(self.response, @"got no response");
    STAssertTrue([self.buffer length] > 0, @"got no data");

    NSError* error = nil;
    NSURL* devNotesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"DevNotes" withExtension:@"txt"];
    NSString* devNotes = [NSString stringWithContentsOfURL:devNotesURL encoding:NSUTF8StringEncoding error:&error];
    NSString* receivedNotes = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
    STAssertTrue([receivedNotes isEqualToString:devNotes], @"received notes didn't match: was:\n%@\n\nshould have been:\n%@", receivedNotes, devNotes);
}

@end
