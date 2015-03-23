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

@class CURLTransferStack, CURLTransfer;
@class CURLSocketRegistration;


@protocol CURLTransferStackDelegate <NSObject>
@end


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
    NSOperationQueue    *_delegateQueue;
    
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

+ (CURLTransferStack*)sharedTransferStack;

/**
 Creates a stack
 */
+ (CURLTransferStack *)transferStackWithDelegate:(id <CURLTransferStackDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;

@property (readonly) NSOperationQueue *delegateQueue;

/**
 * Shut down the multi and clean up all resources that it was using.
 */

- (void)shutdown;

/**  Loading respects as many of NSURLRequest's built-in features as possible, including:
    * An HTTP method of @"HEAD" turns on the CURLOPT_NOBODY option, regardless of protocol (e.g. handy for FTP)
    * Similarly, @"PUT" turns on the CURLOPT_UPLOAD option (again handy for FTP uploads)

    * Supply -HTTPBody or -HTTPBodyStream to switch Curl into uploading mode, regardless of protocol

    * Custom Range: HTTP headers are specially handled to set the CURLOPT_RANGE option, regardless of protocol in use
      (you should still construct the header as though it were HTTP, e.g. bytes=500-999)

    * Custom Accept-Encoding: HTTP headers are specially handled to set the CURLOPT_ENCODING option

  Delegate messages are delivered on the specified queue

  Redirects are *not* automatically followed. If you want that behaviour, NSURLConnection is likely a better match for your needs
 */
- (CURLTransfer *)transferWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential delegate:(id)delegate;

#pragma mark Managing the Stack

/**
 Asynchronously calls a completion callback with all outstanding transfers in the stack.
 
 @param completionHandler This handler is executed on the delegate queue.
 */
- (void)getTransfersWithCompletionHandler:(void (^)(NSArray *transfers))completionHandler;

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
