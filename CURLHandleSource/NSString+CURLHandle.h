//
//  NSString+CURLHandle.h
//  CURLHandle
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import <Foundation/Foundation.h>

@interface NSString (CURLHandle)

- (NSString *) headerStatus;
- (NSString *) headerHTTPVersion;
- (NSString *) headerMatchingKey:(NSString *)inKey;
- (NSArray *) headersMatchingKey:(NSString *)inKey;
- (NSDictionary *) allHTTPHeaderFields;
- (NSString *) headerKey;
- (NSString *) headerValue;
- (NSArray *) componentsSeparatedByLineSeparators;

@end
