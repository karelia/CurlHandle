//
//  CURLMulti.h
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <curl/curl.h>

@class CURLHandle;

/**
 * Wrapper for a curl_multi handle.
 * In general you shouldn't use this class directly - use the extensions in NSURLRequest+CURLHandle
 * instead, and work with normal NSURLConnections.
 *
 * CURLProtocol uses the global sharedInstance to implement the NSURLRequest/NSURLConnection 
 * integration.
 *
 * There's nothing to stop you making other instances if you want to - it's just not really necessary, particularly
 * as we don't expose the curl multi externally.
 *
 * This class works by setting up a serial GCD queue to process all events associated with the multi. We add
 * gcd dispatch sources for each socket that the multi makes, and use them to notify curl when something
 * happens that needs attention.
 */

@interface CURLMulti : NSObject
{
    NSMutableArray* _handles;
    CURLM* _multi;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
}

/**
 * Return a default instance. 
 * Don't call startup or shutdown on this instance - startup will already have been called, and shutting it down
 * will be terminal since it's shared by everything.
 *
 * @return The shared instance.
 */

+ (CURLMulti*)sharedInstance;

- (void)startup;
- (void)shutdown;

- (void)addHandle:(CURLHandle*)handle;
- (void)removeHandle:(CURLHandle*)handle;
- (void)cancelHandle:(CURLHandle*)handle;

- (dispatch_source_t)updateSource:(dispatch_source_t)source type:(dispatch_source_type_t)type socket:(int)socket required:(BOOL)required;

@end
