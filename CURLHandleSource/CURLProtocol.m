//
//  CURLProtocol.m
//
//  Created by Mike Abdullah on 19/01/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLProtocol.h"
#import "CURLRunLoopSource.h"
#import "CURLHandle.h"
#import "NSURLRequest+CURLHandle.h"

@interface CURLProtocol()

@property (strong, nonatomic) CURLHandle* handle;

- (CURLRunLoopSource*)sourceForCurrentRunLoop;

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
    CURLRunLoopSource* source = [self sourceForCurrentRunLoop];

    CURLHandle *handle = [[CURLHandle alloc] init];
    [handle setDelegate:self];

    // Turn automatic redirects off by default, so can properly report them to delegate
    curl_easy_setopt([handle curl], CURLOPT_FOLLOWLOCATION, NO);
    
    [handle loadRequest:[self request] usingSource:source];

    self.handle = handle;
    [handle release];
}

- (void)stopLoading;
{
    CURLRunLoopSource* source = [self sourceForCurrentRunLoop];

    [self.handle cancel];
    [self.handle completeUsingSource:source];
    self.handle = nil;
}

#pragma mark - Utilities


- (CURLRunLoopSource*)sourceForCurrentRunLoop
{
    // TODO: need to create a new source for each run loop?

    static CURLRunLoopSource* gSource = nil;

    if (!gSource)
    {
        gSource = [[CURLRunLoopSource alloc] init];
        [gSource addToRunLoop:[NSRunLoop currentRunLoop]];
    }

    return gSource;
}


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

@end





