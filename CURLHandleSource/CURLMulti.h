//
//  CURLMulti.h
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <curl/curl.h>

@class CURLHandle;

@interface CURLMulti : NSObject
{
    NSThread* _thread;
    CURLM* _multi;
    NSMutableArray* _handles;
    struct timeval _timeout;

}
- (id)init;

- (void)startup;
- (void)shutdown;

- (void)addHandle:(CURLHandle*)handle;
- (void)removeHandle:(CURLHandle*)handle;
- (void)cancelHandle:(CURLHandle*)handle;


@end
