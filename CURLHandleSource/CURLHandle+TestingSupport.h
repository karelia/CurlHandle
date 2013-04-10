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

/** @name Testing Methods */

/**
 Has cancel been called on this handle?

 @warning Not intended for general use.

 @return YES if the handle has been cancelled.
 */

- (BOOL)isCancelled;

/**
 Is this handle managed by a multi?

 @warning Not intended for general use.

 @return YES if the handle is managed by a multi.
 */

- (BOOL)handledByMulti;

/**
 Returns a new CURLMulti, for use in testing.

 Generally multi's are an internal implementation detail, 
 but it's useful to be able to make new ones for unit tests
 since sharing multis between tests can create dependencies.

 @warning Not intended for general use.

 @return A new CURLMulti object.
 */

+ (CURLMulti*)standaloneMultiForTestPurposes;

/**
 Clean up a multi that was created by standaloneMultiForTestPurposes.
 
 @warning Not intended for general use.

 @param multi The multi to clean up.
 */

+ (void)cleanupStandaloneMulti:(CURLMulti*)multi;
@end

