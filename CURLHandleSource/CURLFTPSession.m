//
//  CURLFTPSession.m
//  CURLHandle
//
//  Created by Mike Abdullah on 04/03/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLFTPSession.h"


@implementation CURLFTPSession

- (id)initWithRequest:(NSURLRequest *)request;
{
    NSParameterAssert(request);
    
    if (self = [self init])
    {
        if (![[[request URL] scheme] isEqualToString:@"ftp"])
        {
            [self release]; return nil;
        }
        _request = [request copy];
        
        _handle = [[CURLHandle alloc] init];
        [_handle setDelegate:self];
        if (!_handle)
        {
            [self release];
            return nil;
        }
    }
    
    return self;
}

- (void)dealloc
{
    [_handle release];
    [_request release];
    [_credential release];
    
    [super dealloc];
}

- (void)useCredential:(NSURLCredential *)credential
{
    [_credential release]; _credential = [credential retain];
    
    [_handle setString:[credential user] forKey:CURLOPT_USERNAME];
    [_handle setString:[credential password] forKey:CURLOPT_PASSWORD];
}

- (NSMutableURLRequest *)newMutableRequestWithPath:(NSString *)path isDirectory:(BOOL)isDirectory;
{
    NSMutableURLRequest *request = [_request mutableCopy];
    [request setURL:[[request URL] URLByAppendingPathComponent:path isDirectory:isDirectory]];
    
    return request;
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data permissions:(NSNumber *)permissions error:(NSError **)error;
{
    NSMutableURLRequest *request = [self newMutableRequestWithPath:path isDirectory:NO];
    [request setHTTPBody:data];
    
    BOOL result = [_handle loadRequest:request error:error];
    [request release];
    
    return result;
}

- (BOOL)createDirectoryAtPath:(NSString *)path error:(NSError **)error;
{
    // Navigate to the directory above the one to be created
    // CURLOPT_NOBODY stops libcurl from trying to list the directory's contents
    NSMutableURLRequest *request = [self newMutableRequestWithPath:[path stringByDeletingLastPathComponent] isDirectory:YES];
    [request setHTTPMethod:@"HEAD"];
    
    // Custom command to delete the file once we're in the correct directory
    // CURLOPT_PREQUOTE does much the same thing, but sometimes runs the delete command twice in my testing
    [request curl_setPostTransferCommands:[NSArray arrayWithObject:[@"MKD " stringByAppendingString:[path lastPathComponent]]]];
    
    
    BOOL result = [_handle loadRequest:request error:error];
    [request release];
    return result;
}

- (BOOL)removeFileAtPath:(NSString *)path error:(NSError **)error;
{
    // Navigate to the directory containing the file
    // CURLOPT_NOBODY stops libcurl from trying to list the directory's contents
    NSMutableURLRequest *request = [self newMutableRequestWithPath:[path stringByDeletingLastPathComponent] isDirectory:YES];
    [request setHTTPMethod:@"HEAD"];
    
    // Custom command to delete the file once we're in the correct directory
    // CURLOPT_PREQUOTE does much the same thing, but sometimes runs the delete command twice in my testing
    [request curl_setPostTransferCommands:[NSArray arrayWithObject:[@"DELE " stringByAppendingString:[path lastPathComponent]]]];
    
    BOOL result = [_handle loadRequest:request error:error];
    [request release];
    return result;
}

#pragma mark Delegate

@synthesize delegate = _delegate;

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    [[self delegate] FTPSession:self didReceiveDebugInfo:string ofType:type];
}

@end
