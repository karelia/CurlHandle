//
//  CURLHandleBasedTest
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "KMSTestCase.h"

#import "CURLHandle.h"

@interface CURLHandleBasedTest : KMSTestCase<CURLHandleDelegate>

@property (strong, nonatomic) NSMutableData* buffer;
@property (assign, nonatomic) BOOL cancelled;
@property (strong, nonatomic) NSError* error;
@property (assign, nonatomic) NSUInteger expected;
@property (assign, atomic) BOOL exitRunLoop;
@property (assign, atomic) NSUInteger finishedCount;
@property (strong, nonatomic) NSURLResponse* response;
@property (assign, nonatomic) BOOL sending;

- (BOOL)checkDownloadedBufferWasCorrect;
- (void)runUntilPaused;
- (void)stopServer;

- (NSURL*)ftpTestServer;

@end

