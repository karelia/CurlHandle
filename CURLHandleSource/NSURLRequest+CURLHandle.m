//
//  CURLHandle.m
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.
//
//	The current version of CURLHandle is 2.0
//

#import "NSURLRequest+CURLHandle.h"

@implementation NSURLRequest (CURLOptionsFTP)

- (curl_usessl)curl_desiredSSLLevel;
{
    return [[NSURLProtocol propertyForKey:@"curl_desiredSSLLevel" inRequest:self] longValue];
}

- (BOOL)curl_shouldVerifySSLCertificate;
{
    NSNumber *result = [NSURLProtocol propertyForKey:@"curl_shouldVerifySSLCertificate" inRequest:self];
    return (result ? [result boolValue] : YES);
}

- (NSArray *)curl_postTransferCommands;
{
    return [NSURLProtocol propertyForKey:@"curl_postTransferCommands" inRequest:self];
}

- (NSUInteger)curl_createIntermediateDirectories;
{
    return [[NSURLProtocol propertyForKey:@"curl_createIntermediateDirectories" inRequest:self] unsignedIntegerValue];
}

@end
