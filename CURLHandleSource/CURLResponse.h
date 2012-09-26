//
//  CURLResponse.h
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.

#import <Foundation/Foundation.h>

@interface CURLResponse : NSHTTPURLResponse
{
@private
    NSInteger       _statusCode;
    NSDictionary    *_headerFields;
}

// Implements -initWithURL:statusCode:HTTPVersion:headerFields: on release prior to 10.7.2

@end
