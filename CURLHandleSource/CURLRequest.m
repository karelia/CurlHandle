//
//  CURLRequest.m
//  CURLHandle
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "CURLRequest.h"
#import "CURLProtocol.h"

@implementation NSURLRequest (CURLOptionsFTP)

- (curl_usessl)curl_desiredSSLLevel;
{
    return (curl_usessl)[[NSURLProtocol propertyForKey:@"curl_desiredSSLLevel" inRequest:self] longValue];
}

- (BOOL)curl_shouldVerifySSLCertificate;
{
    NSNumber *result = [NSURLProtocol propertyForKey:@"curl_shouldVerifySSLCertificate" inRequest:self];
    return (result ? [result boolValue] : YES);
}

- (BOOL)curl_shouldVerifySSLHost;
{
    NSNumber *result = [NSURLProtocol propertyForKey:@"curl_shouldVerifySSLHost" inRequest:self];
    return (result ? [result boolValue] : YES);
}

- (NSArray *)curl_preTransferCommands;
{
    return [NSURLProtocol propertyForKey:@"curl_preTransferCommands" inRequest:self];
}

- (NSArray *)curl_postTransferCommands;
{
    return [NSURLProtocol propertyForKey:@"curl_postTransferCommands" inRequest:self];
}

- (NSUInteger)curl_createIntermediateDirectories;
{
    return [[NSURLProtocol propertyForKey:@"curl_createIntermediateDirectories" inRequest:self] unsignedIntegerValue];
}

- (NSNumber *)curl_newFilePermissions; { return [NSURLProtocol propertyForKey:@"curl_newFilePermissions" inRequest:self]; }
- (NSNumber *)curl_newDirectoryPermissions; { return [NSURLProtocol propertyForKey:@"curl_newDirectoryPermissions" inRequest:self]; }

- (NSURL *)curl_SSHKnownHostsFileURL; { return [NSURLProtocol propertyForKey:@"curl_SSHKnownHostsFileURL" inRequest:self]; }

@end

@implementation NSMutableURLRequest (CURLOptionsFTP)

- (void)curl_setDesiredSSLLevel:(curl_usessl)level;
{
    [NSURLProtocol setProperty:[NSNumber numberWithLong:level] forKey:@"curl_desiredSSLLevel" inRequest:self];
}

- (void)curl_setShouldVerifySSLCertificate:(BOOL)verify;
{
    [NSURLProtocol setProperty:@(verify) forKey:@"curl_shouldVerifySSLCertificate" inRequest:self];
}

- (void)curl_setShouldVerifySSLHost:(BOOL)verify;
{
    [NSURLProtocol setProperty:@(verify) forKey:@"curl_shouldVerifySSLHost" inRequest:self];
}

- (void)curl_setCreateIntermediateDirectories:(NSUInteger)value;
{
    [NSURLProtocol setProperty:[NSNumber numberWithUnsignedInteger:value] forKey:@"curl_createIntermediateDirectories" inRequest:self];
}

- (void)curl_setPreTransferCommands:(NSArray *)commands;
{
    if (commands)
    {
        commands = [commands copy];
        [NSURLProtocol setProperty:commands forKey:@"curl_preTransferCommands" inRequest:self];
        [commands release];
    }
    else
    {
        [NSURLProtocol removePropertyForKey:@"curl_preTransferCommands" inRequest:self];
    }
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

- (void)curl_setNewFilePermissions:(NSNumber *)permissions;
{
    [NSURLProtocol setProperty:permissions forKey:@"curl_newFilePermissions" inRequest:self];
}

- (void)curl_setNewDirectoryPermissions:(NSNumber *)permissions;
{
    [NSURLProtocol setProperty:permissions forKey:@"curl_newDirectoryPermissions" inRequest:self];
}

- (void)curl_setSSHKnownHostsFileURL:(NSURL *)url;
{
    if (url)
    {
        [NSURLProtocol setProperty:url forKey:@"curl_SSHKnownHostsFileURL" inRequest:self];
    }
    else
    {
        [NSURLProtocol removePropertyForKey:@"curl_SSHKnownHostsFileURL" inRequest:self];
    }
}

@end

