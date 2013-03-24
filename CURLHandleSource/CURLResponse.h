//
//  CURLResponse.h
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.

#import <Foundation/Foundation.h>

@interface CURLResponse : NSURLResponse
{
@private
    NSString    *_header;
}

// For HTTP URLs, returns an NSHTTPURLResponse. For others, a CURLResponse
+ (NSURLResponse *)responseWithURL:(NSURL *)url statusCode:(NSInteger)statusCode headerString:(NSString *)header;

@property(readonly) NSString *headerString;

@end
