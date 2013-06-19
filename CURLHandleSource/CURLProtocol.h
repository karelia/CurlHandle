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
 NSURLProtocol support for CURLHandle.
 
 This allows you to use NSURLConnection and have it work via a CURLTransfer behind the scenes.
 */

@interface CURLProtocol : NSURLProtocol <CURLTransferDelegate, NSURLAuthenticationChallengeSender>
{
    BOOL _gotResponse;
    CURLTransfer* _transfer;
    BOOL _uploaded;
}

@end
