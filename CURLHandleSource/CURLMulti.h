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
    BOOL _cancelled;
    NSMutableArray* _handles;
    CURLM* _multi;
    NSOperationQueue* _queue;
    struct timeval _timeout;
}

+ (CURLMulti*)sharedInstance;

- (void)startup;
- (void)shutdown;

- (void)addHandle:(CURLHandle*)handle;
- (void)removeHandle:(CURLHandle*)handle;
- (void)cancelHandle:(CURLHandle*)handle;


@end
