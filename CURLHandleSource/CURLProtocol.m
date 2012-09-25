//
//  CURLProtocol.m
//
//  Created by Mike Abdullah on 19/01/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLProtocol.h"
#import "CURLMulti.h"
#import "CURLHandle.h"
#import "NSURLRequest+CURLHandle.h"

@interface CURLProtocol()

@property (strong, nonatomic) CURLHandle* handle;

@end

@implementation CURLProtocol

@synthesize handle = _handle;

#pragma mark - Object Lifecycle

- (void)dealloc
{
    [_handle release];

    [super dealloc];
}

#pragma mark - NSURLProtocol Support

+ (BOOL)canInitWithRequest:(NSURLRequest *)request;
{
    BOOL result = [request shouldUseCurlHandle];
    return result;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading;
{
    CURLMulti* multi = [CURLMulti sharedInstance];

    CURLHandle *handle = [[CURLHandle alloc] init];
    [handle setDelegate:self];

    // Turn automatic redirects off by default, so can properly report them to delegate
    curl_easy_setopt([handle curl], CURLOPT_FOLLOWLOCATION, NO);
    
    [handle loadRequest:[self request] withMulti:multi];

    self.handle = handle;
    [handle release];
}

- (void)stopLoading;
{
    self.handle.delegate = nil;
    if (![self.handle hasCompleted])
    {
        CURLMulti* multi = [CURLMulti sharedInstance];
        [multi cancelHandle:self.handle];
    }

    self.handle = nil;
}

#pragma mark - Utilities


#pragma mark - CURLHandleDelegate

- (void)handle:(CURLHandle *)handle didReceiveResponse:(NSURLResponse *)response;
{
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
}

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data;
{
    [[self client] URLProtocol:self didLoadData:data];
}

- (void)handle:(CURLHandle*)handle didFailWithError:(NSError *)error
{
    [[self client] URLProtocol:self didFailWithError:error];
}

- (void)handleDidFinish:(CURLHandle *)handle
{
    [[self client] URLProtocolDidFinishLoading:self];
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
// TODO: need to pass this info on to the client
}
@end





