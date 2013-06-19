//
//  CURLProtocol.m
//  CURLHandle
//
//  Created by Mike Abdullah on 19/01/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import "CURLProtocol.h"
#import "CURLMultiHandle.h"
#import "CURLTransfer+MultiSupport.h"
#import "NSURLRequest+CURLHandle.h"

@interface CURLProtocol()

@property (assign, nonatomic) BOOL gotResponse;
@property (strong, nonatomic) CURLTransfer* transfer;
@property (assign, nonatomic) BOOL uploaded;

@end

@implementation CURLProtocol

@synthesize gotResponse = _gotResponse;
@synthesize transfer = _transfer;
@synthesize uploaded = _uploaded;

#pragma mark - Object Lifecycle

- (void)dealloc
{
    NSAssert((_transfer == nil) || [_transfer hasCompleted], @"transfer should be done by the time we are destroyed");

    [_transfer release];

    CURLProtocolLog(@"dealloced");

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
    CURLProtocolLog(@"starting");

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
    CURLTransfer *transfer = [[CURLTransfer alloc] initWithRequest:[self request] credential:credential delegate:self delegateQueue:nil];
    self.transfer = transfer;
    [transfer release];
}

- (void)stopLoading;
{
    CURLProtocolLog(@"stopping");
    
    // this protocol object is going away
    // if our associated transfer hasn't completed yet, we need to cancel it, to stop
    // it from trying to send us delegate messages after we've been disposed
    [self.transfer cancel];
    self.transfer = nil;
}

#pragma mark - Utilities

- (NSString*)description
{
    return [NSString stringWithFormat:@"<CURLProtocol %p %@>", self, self.request.URL];
}

#pragma mark - CURLTransferDelegate

- (void)transfer:(CURLTransfer *)transfer didReceiveResponse:(NSURLResponse *)response;
{
    if (!self.gotResponse)
    {
        id <NSURLProtocolClient> client = [self client];
        CURLProtocolLog(@"got didReceiveResponse %ld from %@ for %@", (long)[(NSHTTPURLResponse*)response statusCode], transfer, client);
        [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
        self.gotResponse = YES;
    }
}

- (void)transfer:(CURLTransfer *)transfer didReceiveData:(NSData *)data;
{
    id <NSURLProtocolClient> client = [self client];
    CURLProtocolLog(@"got didReceiveData from %@ for %@", transfer, client);
    [client URLProtocol:self didLoadData:data];
}

- (void)transfer:(CURLTransfer*)transfer didCompleteWithError:(NSError *)error
{
    id <NSURLProtocolClient> client = [self client];
    if (error)
    {
        CURLProtocolLog(@"got didFailWithError %@ from %@ for %@", error, transfer, client);
        [client URLProtocol:self didFailWithError:error];
    }
    else
    {
        CURLProtocolLog(@"got didFinish from %@ for %@", transfer, client);
        [client URLProtocolDidFinishLoading:self];
    }
}

- (void)transfer:(CURLTransfer *)transfer willSendBodyDataOfLength:(NSUInteger)bytesWritten
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





