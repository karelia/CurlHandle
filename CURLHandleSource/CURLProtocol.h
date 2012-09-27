//
//  CURLProtocol.h
//
//  Created by Mike Abdullah on 19/01/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLHandle.h"


@interface CURLProtocol : NSURLProtocol <CURLHandleDelegate, NSURLAuthenticationChallengeSender>
{
    CURLHandle* _handle;
}

@end
