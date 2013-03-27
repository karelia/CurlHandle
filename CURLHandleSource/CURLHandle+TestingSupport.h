//
//  CURLHandle+TestingSupport.h
//
//  Created by Sam Deane on 27/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "CURLHandle.h"

/**
 This functionality is only provided for unit tests, and isn't intended for general use.
 It is included in the framework, so that frameworks that build on this one (eg ConnectionKit) can 
 use these functions in their unit tests.
 */

@interface CURLHandle(TestingSupport)
- (BOOL)isCancelled;
- (BOOL)handledByMulti;
+ (CURLMulti*)standaloneMultiForTestPurposes;
+ (void)cleanupStandaloneMulti:(CURLMulti*)multi;
@end

