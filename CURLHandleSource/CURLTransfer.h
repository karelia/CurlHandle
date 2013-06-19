//
//  CURLTransfer.h
//  CURLHandle
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import <Foundation/Foundation.h>
#import <curl/curl.h>


#ifndef CURLHandleLog
#define CURLHandleLog(...) // no logging by default - to enable it, add something like this to the prefix: #define CURLHandleLog NSLog
#endif

@class CURLMultiHandle;

@protocol CURLTransferDelegate;

extern NSString * const CURLcodeErrorDomain;
extern NSString * const CURLMcodeErrorDomain;
extern NSString * const CURLSHcodeErrorDomain;

typedef NS_ENUM(NSInteger, CURLTransferState) {
    CURLTransferStateRunning = 0,
    CURLTransferStateCanceling = 2,
    CURLTransferStateCompleted = 3,
};

/**
 Wrapper for a CURL easy handle.
 */

@interface CURLTransfer : NSObject
{
	CURL                    *_handle;                         /*" Pointer to the actual CURL object that does all the hard work "*/
    CURLMultiHandle               *_multi;
    NSURLRequest            *_request;
	id <CURLTransferDelegate> _delegate;
    NSOperationQueue        *_delegateQueue;
    CURLTransferState         _state;
    NSError                 *_error;
    
	char                    _errorBuffer[CURL_ERROR_SIZE];	/*" Buffer to hold string generated by CURL; this is then converted to an NSString. "*/
    BOOL                    _executing;                     // debugging
	NSMutableData           *_headerBuffer;                 /*" The buffer that is filled with data from the header as the download progresses; it's appended to one line at a time. "*/
    NSMutableArray          *_lists;                        // Lists we need to hold on to until the handle goes away.
	NSDictionary            *_proxies;                      /*" Dictionary of proxy information; it's released when the transfer is deallocated since it's needed for the transfer."*/
    NSInputStream           *_uploadStream;
}

//  Loading respects as many of NSURLRequest's built-in features as possible, including:
//  
//    * An HTTP method of @"HEAD" turns on the CURLOPT_NOBODY option, regardless of protocol (e.g. handy for FTP)
//    * Similarly, @"PUT" turns on the CURLOPT_UPLOAD option (again handy for FTP uploads)
//  
//    * Supply -HTTPBody or -HTTPBodyStream to switch Curl into uploading mode, regardless of protocol
//  
//    * Custom Range: HTTP headers are specially handled to set the CURLOPT_RANGE option, regardless of protocol in use
//      (you should still construct the header as though it were HTTP, e.g. bytes=500-999)
//  
//    * Custom Accept-Encoding: HTTP headers are specially handled to set the CURLOPT_ENCODING option
//
//  Delegate messages are delivered on an arbitrary thread; you should bounce over a specific thread if required for thread safety, or doing any significant work
//
//  Redirects are *not* automatically followed. If you want that behaviour, NSURLConnection is likely a better match for your needs
- (id)initWithRequest:(NSURLRequest *)request
           credential:(NSURLCredential *)credential
             delegate:(id <CURLTransferDelegate>)delegate
        delegateQueue:(NSOperationQueue *)queue __attribute((nonnull(1)));

@property (readonly, copy) NSURLRequest *originalRequest;  // auth might cause a slightly different request to be sent out

@property (readonly, strong) id <CURLTransferDelegate> delegate; // As an asynchronous API, CURLTransfer retains its delegate until the request is finished, failed, or cancelled. Much like NSURLConnection

/**
 Stops the request as quickly as possible. Will report back a NSURLErrorCancelled to the delegate
 */

- (void)cancel;

/*
 * The current state of the transfer.
 */
@property (readonly) CURLTransferState state;

/*
 * The error, if any, delivered via -transfer:didCompleteWithError:
 * This property will be nil in the event that no error occurred.
 */
@property (readonly, copy) NSError *error;

/**
 CURLINFO_FTP_ENTRY_PATH. Only suitable once transfer has finished.
 
 @return The value of CURLINFO_FTP_ENTRY_PATH.
 */

- (NSString *)initialFTPPath;
+ (NSString *)curlVersion;
+ (NSString*)nameForType:(curl_infotype)type;

@end

#pragma mark - Old API

@interface CURLTransfer(OldAPI)

/** @name Synchronous Methods */

/**
 Perform a request synchronously.

 Please don't use this unless you have to!
 To use, -init a transfer, and then call this method, as many times as you like. Delegate messages will be delivered fairly normally during the request
 To cancel a synchronous request, call -cancel on a different thread and this method will return as soon as it can
 
 @param request The request to perform.
 @param credential A credential to use for the request.
 @param delegate An object to use as the delegate.
 */

- (void)sendSynchronousRequest:(NSURLRequest *)request credential:(NSURLCredential *)credential delegate:(id <CURLTransferDelegate>)delegate;

+ (void) setProxyUserIDAndPassword:(NSString *)inString;
+ (void) setAllowsProxy:(BOOL) inBool;
@end

#pragma mark - Delegate

/**
 Protocol that should be implemented by delegates of CURLTransfer.
 */

@protocol CURLTransferDelegate <NSObject>

/**
 Required protocol method, called when data is received.
 
 @param transfer The transfer receiving the data.
 @param data The new data.
 */

- (void)transfer:(CURLTransfer *)transfer didReceiveData:(NSData *)data;

@optional

/**
 Optional method, called when a response is received.
 
 @param transfer The transfer receiving the response.
 @param response The response.
 */

- (void)transfer:(CURLTransfer *)transfer didReceiveResponse:(NSURLResponse *)response;

/**
 Sent as the last message related to the transfer. Error may be nil, which implies
 that no error occurred and this task is complete.

 Where possible errors are in NSURLErrorDomain or NSCocoaErrorDomain. 
 
 There will generally be a CURLcodeErrorDomain error present; either directly, or as an underlying 
 error (KSError <https://github.com/karelia/KSError> is handy for querying underlying errors).

 The key CURLINFO_RESPONSE_CODE (as an NSNumber) will be filled out with HTTP/FTP status code if appropriate.

 At present all errors include NSURLErrorFailingURLErrorKey and NSURLErrorFailingURLStringErrorKey if applicable even
 though the docs say "This key is only present in the NSURLErrorDomain". Should we respect that?
 
 @param transfer The transfer that has completed.
 @param error The error that it failed with if there was one
 */

- (void)transfer:(CURLTransfer*)transfer didCompleteWithError:(NSError*)error;

/**
 Optional method, called to ask how to transfer a host fingerprint.

 If not implemented, only matching keys are accepted; all else is rejected
 I've found that CURLKHSTAT_FINE_ADD_TO_FILE only bothers appending to the file if not already present

 @param transfer The transfer that's found the fingerprint
 @param foundKey The fingerprint.
 @param knownkey The known fingerprint for the host.
 @param match Whether the fingerprints matched.
 @return A status value indicating what to do.

 */

- (enum curl_khstat)transfer:(CURLTransfer *)transfer didFindHostFingerprint:(const struct curl_khkey *)foundKey knownFingerprint:(const struct curl_khkey *)knownkey match:(enum curl_khmatch)match;

/**
 Optional method, called just before a transfer sends some data.

 Reports a length of 0 when the end of the data is written so you can get a nice heads up that an upload is about to complete.
 
 @param transfer The transfer that is sending data.
 @param bytesWritten The amount of data to be sent. This will be zero when the last data has been written.
 */

- (void)transfer:(CURLTransfer *)transfer willSendBodyDataOfLength:(NSUInteger)bytesWritten;

/**
 Optional method, called to report debug/status information to the delegate.
 
 @param transfer The transfer that the information relates to.
 @param string The information string.
 @param type The type of information.
 */

- (void)transfer:(CURLTransfer *)transfer didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;

@end

#pragma mark - Error Domains

extern NSString * const CURLcodeErrorDomain;
extern NSString * const CURLMcodeErrorDomain;
extern NSString * const CURLSHcodeErrorDomain;

/** 
 CURLHandle support.
 */

@interface NSError(CURLHandle)

/**
 Returns the response code from CURL, if one was set on the error.
 
 @return The response code, or zero if there is no error or no response code was set.
 */

- (NSUInteger)curlResponseCode;
@end

