//
//  CURLHandleBasedTest
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>

#import "CURLHandle.h"

@interface CURLHandleBasedTest : SenTestCase<CURLHandleDelegate>

@property (strong, nonatomic) NSMutableData* buffer;
@property (assign, nonatomic) NSUInteger expected;
@property (assign, atomic) BOOL exitRunLoop;
@property (strong, nonatomic) NSURLResponse* response;
@property (assign, nonatomic) BOOL sending;

- (void)checkDownloadedBufferWasCorrect;

@end

