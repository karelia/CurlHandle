//
//  CURLHandleBasedTest
//  CURLHandle
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import "KMSTestCase.h"

#import "CURLTransfer.h"

@interface CURLHandleBasedTest : KMSTestCase<CURLTransferDelegate>

@property (strong, nonatomic) NSMutableData* buffer;
@property (strong, nonatomic) NSError* error;
@property (assign, nonatomic) NSUInteger expected;
@property (assign, atomic) BOOL exitRunLoop;
@property (assign, atomic) NSUInteger finishedCount;
@property (strong, nonatomic) NSURLResponse* response;
@property (assign, nonatomic) BOOL sending;
@property (strong, nonatomic) NSMutableString* transcript;

- (BOOL)checkDownloadedBufferWasCorrect;
- (void)runUntilPaused;
- (void)stopServer;
- (void)cleanup;

- (NSURL*)ftpTestServer;
- (BOOL)usingMockServer;
- (NSURL*)testFileURL;
- (NSURL*)testFileRemoteURL;

@end

