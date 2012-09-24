//
//  CURLHandle.m
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  This is in the public domain, but please report any improvements back to the author.
//
//	The current version of CURLHandle is 2.0
//

#import "NSMutableURLRequest+CURLHandle.h"

@implementation NSMutableURLRequest (CURLOptionsFTP)

- (void)curl_setDesiredSSLLevel:(curl_usessl)level;
{
    [NSURLProtocol setProperty:[NSNumber numberWithLong:level] forKey:@"curl_desiredSSLLevel" inRequest:self];
}

- (void)curl_setShouldVerifySSLCertificate:(BOOL)verify;
{
    [NSURLProtocol setProperty:[NSNumber numberWithBool:verify] forKey:@"curl_shouldVerifySSLCertificate" inRequest:self];
}

- (void)curl_setPostTransferCommands:(NSArray *)commands;
{
    if (commands)
    {
        commands = [commands copy];
        [NSURLProtocol setProperty:commands forKey:@"curl_postTransferCommands" inRequest:self];
        [commands release];
    }
    else
    {
        [NSURLProtocol removePropertyForKey:@"curl_postTransferCommands" inRequest:self];
    }
}

- (void)curl_setCreateIntermediateDirectories:(NSUInteger)value;
{
    [NSURLProtocol setProperty:[NSNumber numberWithUnsignedInteger:value] forKey:@"curl_createIntermediateDirectories" inRequest:self];
}

@end
