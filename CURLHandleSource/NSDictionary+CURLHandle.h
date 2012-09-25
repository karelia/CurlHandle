//
//  NSDictionary+CURLHandle.h
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.

#import <Foundation/Foundation.h>

@interface NSDictionary(CURLHandle)

- (NSString *) formatForHTTP;
- (NSString *) formatForHTTPUsingEncoding:(NSStringEncoding)inEncoding;
- (NSString *) formatForHTTPUsingEncoding:(NSStringEncoding)inEncoding ordering:(NSArray *)inOrdering;

@end


