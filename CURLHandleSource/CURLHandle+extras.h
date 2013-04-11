//
//  CURLHandle+extras.h
//  CURLHandle
//
//  Created by Dan Wood <dwood@karelia.com> on Mon Oct 01 2001.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "CURLHandle.h"


@interface CURLHandle ( extras )

/*" Set options for the transfer "*/

- (void) setCookieFile:(NSString *)inFilePath;
- (void) setPostString:(NSString *)inPostString;
- (void) setPostDictionary:(NSDictionary *)inDictionary;
- (void) setPostDictionary:(NSDictionary *)inDictionary encoding:(NSStringEncoding) inEncoding;
- (void) setIfModSince:(NSDate *)inModDate;
- (void) setLowSpeedTime:(long) inSeconds;
- (void) setLowSpeedLimit:(long) inBytes;

/*" Get information about the transfer "*/

- (double)downloadContentLength;
- (double)downloadSize;
- (double)downloadSpeed;
- (double)nameLookupTime;
- (double)pretransferTime;
- (double)totalTime;
- (double)uploadContentLength;
- (double)uploadSize;
- (double)uploadSpeed;
- (long)fileTime;
- (long)headerSize;
- (long)requestSize;

/*" Multipart post operations "*/
- (void) setMultipartPostDictionary: (NSDictionary *) inDictionary;
- (void) setMultipartPostDictionary: (NSDictionary *) values headers: (NSDictionary *) headers;


@end
