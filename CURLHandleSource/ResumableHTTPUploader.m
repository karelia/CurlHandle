//
//  ResumableHTTPUploader.m
//
//  Created by Jonathan 'Wolf' Rentzsch on 9/1/06.
//  This is in the public domain, but please report any improvements back to the author.
//

#import "ResumableHTTPUploader.h"
#import "CURLHandle+extras.h"

#warning FIXME This code currently never notices if the socket is severed on the server side.

@implementation ResumableHTTPUploader

- (id)initWithURL:(NSURL*)url_ file:(NSString*)filePath_ client:(id)client_ {
	return [self initWithURL:url_ file:filePath_ user:nil password:nil client:client_];
}

- (id)initWithURL:(NSURL*)url_ file:(NSString*)filePath_ user:(NSString*)user_ password:(NSString*)password_ client:(id)client_ {
	NSParameterAssert(url_);
	NSParameterAssert([[url_ scheme] isEqualToString:@"http"]);
	NSParameterAssert(filePath_);
	// client_ can be nil.
	
	self = [super init];
	if (self) {
		url = [url_ retain];
		curlHandle = [[url_ URLHandleUsingCache:NO] retain];
		if (!curlHandle) {
			[self release];
			return nil;
		}
		filePath = [filePath_ retain];
		client = client_;
		state = ResumableHTTPUploaderHEAD; // Strictly unnecessary since ResumableHTTPUploaderHEAD == 0, but I'm paranoid.
		
		[curlHandle setFailsOnError:YES];
		[curlHandle setFollowsRedirects:NO];
		[curlHandle setNoBody:YES]; // HTTP HEAD
		[curlHandle addClient:self];
		if (user_ && password_)
			[curlHandle setUserName:user_ password:password_];
		[curlHandle loadInBackground];
		if ([client respondsToSelector:@selector(resumableHTTPUploader:currentSize:totalSize:)]) {
			timer = [NSTimer scheduledTimerWithTimeInterval:1.0
													 target:self
												   selector:@selector(poll:)
												   userInfo:nil
													repeats:YES];
		}
	}
	return self;
}

- (void)dealloc {
	[filePath release];
	[curlHandle release];
	[url release];
	[timer invalidate]; timer = nil;
	[super dealloc];
}

- (void)URLHandleResourceDidBeginLoading:(NSURLHandle*)sender {
	assert(sender == curlHandle);
	if ([client respondsToSelector:@selector(resumableHTTPUploaderResourceDidBeginLoading:)]) {
		[client resumableHTTPUploaderResourceDidBeginLoading:self];
	}
	if ([client respondsToSelector:@selector(resumableHTTPUploader:currentSize:totalSize:)]) {
		[client resumableHTTPUploader:self currentSize:0 totalSize:0];
	}
}

- (void)URLHandle:(NSURLHandle*)sender resourceDataDidBecomeAvailable:(NSData*)newBytes {
	assert(sender == curlHandle);
	if ([client respondsToSelector:@selector(resumableHTTPUploader:resourceDataDidBecomeAvailable:)]) {
		[client resumableHTTPUploader:self resourceDataDidBecomeAvailable:newBytes];
	}
}

- (void)curlHandleLoadInBackgroundWorkAround:(id)ignored {
	//	If you call [curlHandle loadInBackground] directly from within the NSURLHandleClient callbacks, it bails with a URLHandleResourceDidCancelLoading.
	//	This work-around delays the -loadInBackground call until after the call stack unwinds.
	[curlHandle loadInBackground];
}

- (void)URLHandle:(NSURLHandle*)sender resourceDidFailLoadingWithReason:(NSString*)reason {
	assert(sender == curlHandle);
	
	if ([curlHandle httpCode] == 404) {
		//	File isn't present on the server yet: upload it.
		[curlHandle setNoBody:NO]; // HTTP PUT
		[curlHandle setPutFile:filePath resumeUploadFromOffset:0];
		state = ResumableHTTPUploaderPUT;
		[self performSelector:@selector(curlHandleLoadInBackgroundWorkAround:) withObject:nil afterDelay:0.0];
	} else {
		//	Another type of error.
		NSLog(@"resourceDidFailLoadingWithReason:%@", reason);
		state = ResumableHTTPUploaderDONE;
		if ([client respondsToSelector:@selector(resumableHTTPUploader:resourceDidFailLoadingWithReason:)]) {
			[client resumableHTTPUploader:self resourceDidFailLoadingWithReason:reason];
		}
	}
}

- (void)URLHandleResourceDidCancelLoading:(NSURLHandle*)sender {
	assert(sender == curlHandle);
	if ([client respondsToSelector:@selector(resumableHTTPUploaderResourceDidCancelLoading:)]) {
		[client resumableHTTPUploaderResourceDidCancelLoading:self];
	}
}

- (void)URLHandleResourceDidFinishLoading:(NSURLHandle*)sender {
	assert(sender == curlHandle);
	
	switch (state) {
		case ResumableHTTPUploaderHEAD: {
			//	HTTP HEAD success.
			uint64_t localFileSize = [[[NSFileManager defaultManager] fileAttributesAtPath:filePath traverseLink:NO] fileSize];
			uint64_t remoteFileSize = atoll([[[curlHandle headerString] headerMatchingKey:@"content-length"] UTF8String]);
			if (remoteFileSize < localFileSize) {
				//	Need to upload the rest of the file.
				[curlHandle setNoBody:NO]; // HTTP PUT
				[curlHandle setPutFile:filePath resumeUploadFromOffset:remoteFileSize];
				state = ResumableHTTPUploaderPUT;
				[self performSelector:@selector(curlHandleLoadInBackgroundWorkAround:) withObject:nil afterDelay:0.0];
			} else {
				state = ResumableHTTPUploaderDONE;
				if ([client respondsToSelector:@selector(resumableHTTPUploaderResourceDidFinishLoading:)]) {
					[client resumableHTTPUploaderResourceDidFinishLoading:self];
				}
				if ([client respondsToSelector:@selector(resumableHTTPUploader:currentSize:totalSize:)]) {
					[client resumableHTTPUploader:self currentSize:localFileSize totalSize:localFileSize];
				}
			}
			} break;
		case ResumableHTTPUploaderPUT:
			//	HTTP PUT success.
			state = ResumableHTTPUploaderDONE;
			if ([client respondsToSelector:@selector(resumableHTTPUploaderResourceDidFinishLoading:)]) {
				[client resumableHTTPUploaderResourceDidFinishLoading:self];
			}
			if ([client respondsToSelector:@selector(resumableHTTPUploader:currentSize:totalSize:)]) {
				[client resumableHTTPUploader:self currentSize:[curlHandle uploadSize] totalSize:[curlHandle uploadContentLength]];
			}
			break;
		case ResumableHTTPUploaderDONE:
			assert(0);
			break;
		default:
			assert(0);
	}
}

- (void)poll:(NSTimer*)timer_ {
	switch (state) {
		case ResumableHTTPUploaderHEAD:
			// Already sent in -URLHandleResourceDidBeginLoading.
			break;
		case ResumableHTTPUploaderPUT:
			[client resumableHTTPUploader:self currentSize:[curlHandle uploadSize] totalSize:[curlHandle uploadContentLength]];
			break;
		case ResumableHTTPUploaderDONE:
			[timer invalidate]; timer = nil;
			// Already sent -URLHandleResourceDidFinishLoading.
			break;
		default:
			assert(0);
	}
}

- (ResumableHTTPUploaderState)state {
	return state;
}

@end
