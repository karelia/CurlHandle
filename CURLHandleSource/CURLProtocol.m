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
@property (strong, nonatomic) CURLMulti* multi;
@property (assign, nonatomic) BOOL uploaded;
@end

@implementation CURLProtocol

@synthesize handle = _handle;
@synthesize multi = _multi;
@synthesize uploaded = _uploaded;

#pragma mark - Object Lifecycle

- (void)dealloc
{
    [_handle release];
    [_multi release];
    
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
    // Request auth before trying FTP connection
    NSURL *url = [[self request] URL];
    NSString *scheme = [url scheme];
    
    if ([@"ftp" caseInsensitiveCompare:scheme] == NSOrderedSame || [@"ftps" caseInsensitiveCompare:scheme] == NSOrderedSame)
    {
        NSString *protocol = ([@"ftps" caseInsensitiveCompare:scheme] == NSOrderedSame ? @"ftps" : NSURLProtectionSpaceFTP);
        
        NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:[url host]
                                                                            port:[[url port] integerValue]
                                                                        protocol:protocol
                                                                           realm:nil
                                                            authenticationMethod:NSURLAuthenticationMethodDefault];
        
        NSURLCredential *credential = [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:space];
        
        NSURLAuthenticationChallenge *challenge = [[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space
                                                                                             proposedCredential:credential
                                                                                           previousFailureCount:0
                                                                                                failureResponse:nil
                                                                                                          error:nil
                                                                                                         sender:self];
        
        [space release];
        
        [[self client] URLProtocol:self didReceiveAuthenticationChallenge:challenge];
        [challenge release];
        
        return;
    }
    
    [self startLoadingWithCredential:nil];
}

- (void)startLoadingWithCredential:(NSURLCredential *)credential;
{
    self.multi = [CURLMulti sharedInstance]; // in theory we don't need to retain this, since it's a singleton, but we do in case something (a unit testing scenario for example) messes with it before we're done
    CURLHandle *handle = [[CURLHandle alloc] initWithRequest:[self request] credential:credential delegate:self multi:self.multi];
    self.handle = handle;
    [handle release];
}

- (void)stopLoading;
{
    // this protocol object is going away
    // if our associated handle hasn't completed yet, we need to cancel it, to stop
    // it from trying to send us delegate messages after we've been disposed
    if (![self.handle hasCompleted])
    {
        [self.multi cancelHandle:self.handle];
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

- (void)handleWasCancelled:(CURLHandle *)handle
{
    self.handle = nil;
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    // TODO: improve this if we're ever given acess
    // ideally we'd be able to generate a connection:didSendBodyData:totalBytesWritten:totalBytesExpectedToWrite: call here
    // but NSURLProtocol doesn't give us a way to do it

    // is the upload finished?
    if (bytesWritten == 0)
    {
        // set a flag so that when stopLoading is called, we don't cancel incorrectly 
        self.uploaded = YES;
    }
}

#pragma mark NSURLAuthenticationChallengeSender

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [self startLoadingWithCredential:credential];
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [self startLoadingWithCredential:nil];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [[self client] URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                         code:NSURLErrorUserAuthenticationRequired
                                                                     userInfo:nil]];
}

@end





