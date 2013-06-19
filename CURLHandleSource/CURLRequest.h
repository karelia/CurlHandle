//
//  CURLRequest.h
//  CURLHandle
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import <Foundation/Foundation.h>
#import <curl/curl.h>

@interface NSURLRequest (CURLOptionsFTP)

// CURLUSESSL_NONE, CURLUSESSL_TRY, CURLUSESSL_CONTROL, or CURLUSESSL_ALL
@property(nonatomic, readonly) curl_usessl curl_desiredSSLLevel;

@property(nonatomic, readonly) BOOL curl_shouldVerifySSLCertificate;    // CURLOPT_SSL_VERIFYPEER

// An array of strings. Executed in turn before/after the main request is done
// NOTE: We have seen crashes (mishandling of buffers) when using post-transfer commands for a request that doesn't actually do a transfer. This may be a bug in libcurl; we don't know yet!
@property(nonatomic, copy, readonly) NSArray *curl_postTransferCommands;
@property(nonatomic, copy, readonly) NSArray *curl_preTransferCommands;

// A value greater than 0 will cause Curl to create missing directories. I'm pretty certain this only applies when uploading
// Default is 0
// See CURLOPT_FTP_CREATE_MISSING_DIRS docs for full details
@property(nonatomic, readonly) NSUInteger curl_createIntermediateDirectories;

// Default is nil, which tells libcurl in turn to use its own defaults, which are currently documented to be 0644 and 0755 respectively
// Only supported by SFTP, SCP and file protocols at present apparently
@property(nonatomic, readonly) NSNumber *curl_newFilePermissions;
@property(nonatomic, readonly) NSNumber *curl_newDirectoryPermissions;

// Default is nil, which means no checking
@property(nonatomic, readonly) NSURL *curl_SSHKnownHostsFileURL;

@end

@interface NSMutableURLRequest (CURLOptionsFTP)

- (void)curl_setDesiredSSLLevel:(curl_usessl)level;
- (void)curl_setShouldVerifySSLCertificate:(BOOL)verify;
- (void)curl_setCreateIntermediateDirectories:(NSUInteger)createIntermediateDirectories;

- (void)curl_setPreTransferCommands:(NSArray *)commands;
- (void)curl_setPostTransferCommands:(NSArray *)commands;

- (void)curl_setNewFilePermissions:(NSNumber *)permissions;
- (void)curl_setNewDirectoryPermissions:(NSNumber *)permissions;

- (void)curl_setSSHKnownHostsFileURL:(NSURL *)url;

@end





