//
//  NSDictionary+CURLHandle.h
//  CURLHandle
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import <Foundation/Foundation.h>

@interface NSDictionary(CURLHandle)

- (NSString *) formatForHTTP;
- (NSString *) formatForHTTPUsingEncoding:(NSStringEncoding)inEncoding;
- (NSString *) formatForHTTPUsingEncoding:(NSStringEncoding)inEncoding ordering:(NSArray *)inOrdering;

@end


