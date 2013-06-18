//
//  CURLMultiHandle.h
//  CURLHandle
//
//  Created by Sam Deane on 20/09/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <curl/curl.h>

#ifndef CURLMultiLog
#define CURLMultiLog(...) // no logging by default - to enable it, add something like this to the prefix: #define CURLMultiLog NSLog
#endif

#ifndef CURLMultiLogError
#define CURLMultiLogError NSLog
#endif

#ifndef CURLMultiLogDetail
#define CURLMultiLogDetail CURLMultiLog
#endif

@class CURLHandle;
@class CURLSocket;

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

@interface CURLMultiHandle : NSObject
{
    CURLM *_multi;
    NSMutableArray* _handles;
    NSMutableArray* _sockets;
    dispatch_queue_t _queue;
    
    dispatch_source_t   _timer;
    BOOL                _timerIsSuspended;
}

/**
 * Return a default instance. 
 * Don't call startup or shutdown on this instance - startup will already have been called, and shutting it down
 * will be terminal since it's shared by everything.
 *
 * @return The shared instance.
 */

+ (CURLMultiHandle*)sharedInstance;


/** Prepare the multi for work. Needs to be called once before addHandle is called. Should be matched with a call to shutdown
 * before the multi is destroyed.
 */

- (void)startup;

/** 
 * Shut down the multi and clean up all resources that it was using.
 */

- (void)shutdown;

/**
 * Assign a CURLHandle to the multi to manage.
 * CURLHandle uses this method internally when you call loadRequest:withMulti: on a handle,
 * so generally you don't need to call it directly.
 * The multi will retain the handle for as long as it needs it, but will silently release it once
 * the handle's upload/download has completed or failed.
 *
 * @param handle The handle to manage. Will be retained by the multi until removed (completion automatically performs removal).
 */

- (void)addHandle:(CURLHandle*)handle;

/** 
 * This removes the handle from the multi. *
 * It is safe to call this method for a handle that has already been cancelled, or has completed,
 * (or indeed was never managed by the multi). Doing so will simply do nothing.
 *
 * @warning ONLY call this on the receiver's queue
 *
 * To cancel the handle, call [handle cancel] instead - it will end up calling this method too,
 * if the handle was being managed by a multi.
 *
 * @param handle The handle to cancel. Should have previously been added with manageHandle:.
 */

- (void)removeHandle:(CURLHandle*)handle;

/**
 Update the dispatch source for a given socket and type.
 
 @warning The routine is used internally by <CURLMulti> / <CURLSocket>, and shouldn't be called from your code.

 @param source The current dispatch source for the given type
 @param type Is this the source for reading or writing?
 @param socket The <CURLSocket> object that owns the source.
 @param raw The raw system socket that the dispatch source should be monitoring.
 @param required Is the source required? If not, an existing source will be cancelled. If required and the source parameter is nil, and new one will be created.
 @return The new/updated dispatch source.
*/

- (dispatch_source_t)updateSource:(dispatch_source_t)source type:(dispatch_source_type_t)type socket:(CURLSocket*)socket raw:(int)raw required:(BOOL)required;

/**
 The serial queue the instance schedules sources on
 */
@property (readonly, assign, nonatomic) dispatch_queue_t queue;

@end
