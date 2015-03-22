//
//  CURLTransfer+MultiSupport.h
//  CURLHandle
//
//  Created by Sam Deane on 27/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "CURLTransfer.h"
#import "CURLTransferStack.h"


/**
 Private API used by CURLMulti.
 Not exported in the framework, and not recommended for general use.
 */


@interface CURLTransferStack (Private)

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

@end


@interface CURLTransfer(MultiSupport)

- (id)initWithRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential delegate:(id <CURLTransferDelegate>)delegate delegateQueue:(NSOperationQueue *)queue stack:(CURLTransferStack *)stack __attribute((nonnull(1,3,4)));

/** @name Internal Methods */

/**
 The CURL handle managed by this object.

 @warning Not intended for general use.

 @return The curl handle.

 */

- (CURL*)curlHandle;

/**
 Called by <CURLMulti> to tell the transfer that it has completed.
 
 @param code The completion code.
 
 @warning Not intended for general use.

 */

- (void)completeWithCode:(CURLcode)code;

/**
 Called by <CURLMulti> to tell the transfer that it has completed.
 
 @param error The failure error if there was one.
 
 @warning Not intended for general use.
 
 */

- (void)completeWithError:(NSError *)error;

/**
 Has the transfer completed?
 
 @return YES if the transfer has completed.
 
 @warning Not intended for general use.

 */

- (BOOL)hasCompleted;

@end

