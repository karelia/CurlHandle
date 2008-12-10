//
//  ResumableHTTPUploader.m
//
//  Created by Jonathan 'Wolf' Rentzsch on 9/1/06.
//  This is in the public domain, but please report any improvements back to the author.
//

#import "CURLHandle.h"

typedef enum {
	ResumableHTTPUploaderHEAD,
	ResumableHTTPUploaderPUT,
	ResumableHTTPUploaderDONE
} ResumableHTTPUploaderState;

@interface ResumableHTTPUploader : NSObject <NSURLHandleClient> {
	NSURL						*url;
	CURLHandle					*curlHandle;
	NSString					*filePath;
	id							client;
	ResumableHTTPUploaderState	state;
	NSTimer						*timer;
}
- (id)initWithURL:(NSURL*)url_ file:(NSString*)filePath_ client:(id)client_;
- (id)initWithURL:(NSURL*)url_ file:(NSString*)filePath_ user:(NSString*)user_ password:(NSString*)password_ client:(id)client_;
- (ResumableHTTPUploaderState)state;
@end

@interface NSObject (ResumableHTTPUploaderClient)
- (void)resumableHTTPUploader:(ResumableHTTPUploader *)sender
				  currentSize:(double)currentSize	// Number of bytes transferred so far.
					totalSize:(double)totalSize;	// Total number of bytes remaining to upload. NOT the size of the source file.

- (void)resumableHTTPUploader:(ResumableHTTPUploader *)sender resourceDataDidBecomeAvailable:(NSData *)newBytes;
- (void)resumableHTTPUploaderResourceDidBeginLoading:(ResumableHTTPUploader *)sender;
- (void)resumableHTTPUploaderResourceDidFinishLoading:(ResumableHTTPUploader *)sender;
- (void)resumableHTTPUploaderResourceDidCancelLoading:(ResumableHTTPUploader *)sender;
- (void)resumableHTTPUploader:(ResumableHTTPUploader *)sender resourceDidFailLoadingWithReason:(NSString *)reason;
@end