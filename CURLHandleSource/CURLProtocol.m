//
//  CURLProtocol.m
//  CURLHandle
//
//  Created by Mike Abdullah on 19/01/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLProtocol.h"
#import "CURLRunLoopSource.h"
#import "CURLHandle.h"

@implementation CURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request;
{
    BOOL result = [request shouldUseCurlHandle];
    return result;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request; { return request; }

- (id)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id <NSURLProtocolClient>)client
{
    if ((self = [super initWithRequest:request cachedResponse:cachedResponse client:client]))
    {
        CURLHandleLog(@"made new protocol object %@", self);
    }

    return self;
}

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

- (void)startLoading;
{
    CURLRunLoopSource* source = [self sourceForCurrentRunLoop];

    CURLHandle *handle = [[CURLHandle alloc] init];
    [handle setDelegate:self];

    // Turn automatic redirects off by default, so can properly report them to delegate
    curl_easy_setopt([handle curl], CURLOPT_FOLLOWLOCATION, NO);
    
    [handle loadRequest:[self request] usingSource:source];

    [handle release];
}

- (void)stopLoading;
{
    // TODO: Instruct handle to cancel
}

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


@implementation NSURLRequest (CURLProtocol)

- (BOOL)shouldUseCurlHandle;
{
    return [[NSURLProtocol propertyForKey:@"useCurlHandle" inRequest:self] boolValue];
}

@end


@implementation NSMutableURLRequest (CURLProtocol)

- (void)setShouldUseCurlHandle:(BOOL)useCurl;
{
    [NSURLProtocol setProperty:[NSNumber numberWithBool:useCurl] forKey:@"useCurlHandle" inRequest:self];
    [NSURLProtocol registerClass:[CURLProtocol class]];
}

@end





