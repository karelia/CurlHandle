//
//  CURLHandle.h
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.

#import <Foundation/Foundation.h>
#import <curl/curl.h>

@interface NSURLRequest (CURLOptionsFTP)

// CURLUSESSL_NONE, CURLUSESSL_TRY, CURLUSESSL_CONTROL, or CURLUSESSL_ALL
@property(nonatomic, readonly) curl_usessl curl_desiredSSLLevel;

@property(nonatomic, readonly) BOOL curl_shouldVerifySSLCertificate;    // CURLOPT_SSL_VERIFYPEER

// An array of strings. Executed in turn once the main request is done
@property(nonatomic, copy, readonly) NSArray *curl_postTransferCommands;

// A value greater than 0 will cause Curl to create missing directories. I'm pretty certain this only applies when uploading
// Default is 0
// See CURLOPT_FTP_CREATE_MISSING_DIRS docs for full details
@property(nonatomic, readonly) NSUInteger curl_createIntermediateDirectories;

@end

@interface NSMutableURLRequest (CURLOptionsFTP)

- (void)curl_setDesiredSSLLevel:(curl_usessl)level;
- (void)curl_setShouldVerifySSLCertificate:(BOOL)verify;
- (void)curl_setPostTransferCommands:(NSArray *)postTransferCommands;
- (void)curl_setCreateIntermediateDirectories:(NSUInteger)createIntermediateDirectories;

@end





