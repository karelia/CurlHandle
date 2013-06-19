//
//  CURLProtocol.h
//  CURLHandle
//
//  Created by Mike Abdullah on 19/01/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import "CURLTransfer.h"

#ifndef CURLProtocolLog
#define CURLProtocolLog(...) // no logging by default - to enable it, add something like this to the prefix: #define CURLHandleLog NSLog
#endif

/**
 An NSURLProtocol subclass implemented by handing off requests to libcurl via CURLTransfer.
 
 This allows you to use the Cocoa URL Loading System's APIs, but have it work
 using CURLHandle behind the scenes.
 */

@interface CURLProtocol : NSURLProtocol <CURLTransferDelegate, NSURLAuthenticationChallengeSender>
{
    BOOL _gotResponse;
    CURLTransfer* _transfer;
    BOOL _uploaded;
}

@end


@interface NSURLRequest (CURLProtocol)

/**
 @return Whether the Cocoa URL Loading System should attempt to use CURLHandle for this request.
 */
- (BOOL)shouldUseCurlHandle;

@end


@interface NSMutableURLRequest (CURLProtocol)
/**
 Setting to YES automatically registers CURLProtocol with NSURLProtocol. You can do so earlier, manually if required
 
 @param useCurl should this request use CURL?
 */

- (void)setShouldUseCurlHandle:(BOOL)useCurl;
@end
