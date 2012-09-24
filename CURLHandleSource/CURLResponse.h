//
//  CURLHandle.h
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.
//
//	The current version of CURLHandle is 1.9.
//

#import <Foundation/Foundation.h>

@interface CURLResponse : NSHTTPURLResponse
{
@private
    NSInteger       _statusCode;
    NSDictionary    *_headerFields;
}

- (id)initWithURL:(NSURL *)URL statusCode:(NSInteger)statusCode headerString:(NSString *)headerString;

@end
