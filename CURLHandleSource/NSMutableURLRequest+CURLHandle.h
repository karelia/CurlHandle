//
//  CURLHandle.h
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.
//
//	The current version of CURLHandle is 1.9.
//

#import <Foundation/Foundation.h>

#import <curl/curl.h>

@interface NSMutableURLRequest (CURLOptionsFTP)

- (void)curl_setDesiredSSLLevel:(curl_usessl)level;
- (void)curl_setShouldVerifySSLCertificate:(BOOL)verify;
- (void)curl_setPostTransferCommands:(NSArray *)postTransferCommands;
- (void)curl_setCreateIntermediateDirectories:(NSUInteger)createIntermediateDirectories;

@end



