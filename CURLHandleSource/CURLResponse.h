//
//  CURLResponse.h
//  CURLHandle
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import <Foundation/Foundation.h>

@interface CURLResponse : NSURLResponse
{
@private
    NSInteger   _code;
    NSString    *_header;
}

// For HTTP URLs, returns an NSHTTPURLResponse. For others, a CURLResponse
+ (NSURLResponse *)responseWithURL:(NSURL *)url statusCode:(NSInteger)statusCode headerString:(NSString *)header;

@property(readonly) NSInteger statusCode;
@property(readonly) NSString *headerString;

@end
