//
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

@class CURLTransfer;
@class CURLSocketRegistration;

/**
 * Wrapper for a curl_multi handle.
 * Roughly analogous to NSURLSession for curl.
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

@interface CURLTransferStack : NSObject
{
    CURLM *_multi;
    NSMutableArray* _transfers;
    BOOL            _isRunningProcessingLoop;
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

+ (CURLTransferStack*)sharedInstance;


/**
 * Shut down the multi and clean up all resources that it was using.
 */

- (void)shutdown;

/**
 * Assign a CURLTransfer to the multi to manage.
 * CURLTransfer uses this method internally when you call loadRequest:withMulti: on a transfer,
 * so generally you don't need to call it directly.
 * The multi will retain the transfer for as long as it needs it, but will silently release it once
 * the transfer has completed or failed.
 *
 * @param transfer The transfer to manage. Will be retained by the multi until removed (completion automatically performs removal).
 */

- (void)beginTransfer:(CURLTransfer*)transfer __attribute((nonnull));

/** 
 * This removes the transfer from the multi. *
 * It is safe to call this method for a transfer that has already been cancelled, or has completed,
 * (or indeed was never managed by the multi). Doing so will simply do nothing.
 *
 * @warning ONLY call this on the receiver's queue
 *
 * To cancel the transfer, call [transfer cancel] instead - it will end up calling this method too,
 * if the transfer was being managed by a multi.
 *
 * @param transfer The transfer to cancel. Should have previously been added with beginTransfer:.
 */

- (void)suspendTransfer:(CURLTransfer*)transfer __attribute((nonnull));

/**
 Update the dispatch source for a given socket and type.
 
 @warning The routine is used internally by <CURLMulti> / <CURLSocket>, and shouldn't be called from your code.

 @param source The current dispatch source for the given type
 @param type Is this the source for reading or writing?
 @param socket The raw system socket that the dispatch source should be monitoring.
 @param registration The <CURLSocketRegistration> object that owns the source.
 @param required Is the source required? If not, an existing source will be cancelled. If required and the source parameter is nil, and new one will be created.
 @return The new/updated dispatch source.
*/

- (dispatch_source_t)updateSource:(dispatch_source_t)source type:(dispatch_source_type_t)type socket:(int)socket registration:(CURLSocketRegistration *)registration required:(BOOL)required;

/**
 The serial queue the instance schedules sources on
 */
@property (readonly, assign, nonatomic) dispatch_queue_t queue;

@end
