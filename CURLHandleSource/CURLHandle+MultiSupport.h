//
//  CURLHandle+MultiSupport.h
//
//  Created by Sam Deane on 27/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "CURLHandle.h"

/**
 Private API used by CURLMulti.
 Not exported in the framework.
 */

@interface CURLHandle(MultiSupport)
- (CURL *) curl;
- (void)completeWithMultiCode:(CURLMcode)code;
- (void)completeWithCode:(CURLcode)code;
- (BOOL)hasCompleted;
- (BOOL)isCancelled;
- (BOOL)handledByMulti;
- (void)removedByMulti:(CURLMulti*)multi;
@end

