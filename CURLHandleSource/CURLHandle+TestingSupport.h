//
//  CURLHandle+TestingSupport.h
//  CURLHandle
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
 Creates a CURLHandle instance tied to a specific multi handle
 
 @warning Not intended for general use.
 
 @return A new CURLHandle object.
 */
- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential delegate:(id <CURLHandleDelegate>)delegate multi:(CURLMultiHandle*)multi __attribute((nonnull(1,4)));

/**
 Returns a new CURLMulti, for use in testing.

 Generally multi's are an internal implementation detail, 
 but it's useful to be able to make new ones for unit tests
 since sharing multis between tests can create dependencies.

 @warning Not intended for general use.

 @return A new CURLMulti object.
 */

+ (CURLMultiHandle*)standaloneMultiForTestPurposes;

/**
 Clean up a multi that was created by standaloneMultiForTestPurposes.
 
 @warning Not intended for general use.

 @param multi The multi to clean up.
 */

+ (void)cleanupStandaloneMulti:(CURLMultiHandle*)multi;
@end

