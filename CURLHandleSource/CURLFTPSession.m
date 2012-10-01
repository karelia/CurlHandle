//
//  CURLFTPSession.m
//
//  Created by Mike Abdullah on 04/03/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLFTPSession.h"
#import "NSURLRequest+CURLHandle.h"


@interface CURLFTPTransfer : NSObject <CURLHandleDelegate>
{
  @private
    CURLFTPSession  *_session;
    
    void    (^_completionHandler)(CURLHandle *handle, NSError *error);
    void    (^_dataBlock)(NSData *data);
    void    (^_progressBlock)(NSUInteger bytesWritten);
}

- (id)initWithRequest:(NSURLRequest *)request
              session:(CURLFTPSession *)session
          dataHandler:(void (^)(NSData *data))dataBlock
    completionHandler:(void (^)(CURLHandle *handle, NSError *error))handler;

- (id)initWithRequest:(NSURLRequest *)request
              session:(CURLFTPSession *)session
        progressBlock:(void (^)(NSUInteger bytesWritten))progressBlock
    completionHandler:(void (^)(CURLHandle *handle, NSError *error))handler;

@end


@implementation CURLFTPSession

#pragma mark Lifecycle

- (id)initWithRequest:(NSURLRequest *)request;
{
    NSParameterAssert(request);
    
    if (self = [self init])
    {
        if (![self validateRequest:request])
        {
            [self release]; return nil;
        }
        _request = [request copy];
    }
    
    return self;
}

- (void)dealloc
{
    [_request release];
    [_credential release];
    [_opsAwaitingAuth release];
    
    [super dealloc];
}

#pragma mark Requests

@synthesize baseRequest = _request;
- (void)setBaseRequest:(NSURLRequest *)request;
{
    NSParameterAssert([self validateRequest:request]);
    
    request = [request copy];
    [_request release]; _request = request;
}

- (BOOL)validateRequest:(NSURLRequest *)request;
{
    NSString *scheme = [[request URL] scheme];
    return ([@"ftp" caseInsensitiveCompare:scheme] == NSOrderedSame || [@"ftps" caseInsensitiveCompare:scheme] == NSOrderedSame);
}

- (NSMutableURLRequest *)newMutableRequestWithPath:(NSString *)path isDirectory:(BOOL)isDirectory;
{
    NSMutableURLRequest *request = [_request mutableCopy];
    if ([path length])  // nil/empty paths should only occur when trying to CWD to the home directory
    {
        // Special case: Root directory when _request is a pathless URL (e.g. ftp://example.com ) needs a second slash to tell Curl it's absolute
        //if ([path isEqualToString:@"/"]) path = @"//";
        
        if ([path isAbsolutePath])
        {
            // It turns out that to list root, you need a URL like ftp://example.com//./
            if ([path length] == 1) path = @"/.";
        }
        
        if (isDirectory)
        {
            if (![path hasSuffix:@"/"] || [path isEqualToString:@"/"])
            {
                path = [path stringByAppendingString:@"/"];
            }
        }
        else
        {
            while ([path hasSuffix:@"/"])
            {
                path = [path substringToIndex:[path length] - 1];
            }
        }
        
        [request setURL:[[self class] URLWithPath:path relativeToURL:[request URL]]];
    }
    
    return request;
}

#pragma mark Operations

- (void)executeCustomCommands:(NSArray *)commands
                  inDirectory:(NSString *)directory
createIntermediateDirectories:(BOOL)createIntermediates
            completionHandler:(void (^)(NSError *error))handler;
{
    // Navigate to the directory
    // @"HEAD" => CURLOPT_NOBODY, which stops libcurl from trying to list the directory's contents
    // If the connection is already at that directory then curl wisely does nothing
    NSMutableURLRequest *request = [self newMutableRequestWithPath:directory isDirectory:YES];
    [request setHTTPMethod:@"HEAD"];
    [request curl_setCreateIntermediateDirectories:createIntermediates];
    
    // Custom commands once we're in the correct directory
    // CURLOPT_PREQUOTE does much the same thing, but sometimes runs the command twice in my testing
    [request curl_setPostTransferCommands:commands];
    
    [self sendRequest:request dataHandler:nil completionHandler:^(CURLHandle *handle, NSError *error) {
            handler(error);
    }];
    
    [request release];
}

- (void)doAuthThenPerformBlock:(void (^)(void))block;
{
    // First demand auth
    if (!_opsAwaitingAuth)
    {
        _opsAwaitingAuth = [[NSOperationQueue alloc] init];
        [_opsAwaitingAuth setSuspended:YES];
        
        NSURL *url = [[self baseRequest] URL];
        NSString *protocol = ([@"ftps" caseInsensitiveCompare:[url scheme]] == NSOrderedSame ? @"ftps" : NSURLProtectionSpaceFTP);
        
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
        
        [[self delegate] FTPSession:self didReceiveAuthenticationChallenge:challenge];
        [challenge release];
    }
    
    
    // Will run pretty much immediately once we're authenticated
    [_opsAwaitingAuth addOperationWithBlock:block];
}

- (void)sendRequest:(NSURLRequest *)request dataHandler:(void (^)(NSData *data))dataBlock completionHandler:(void (^)(CURLHandle *handle, NSError *error))handler;
{
    [self doAuthThenPerformBlock:^{
        CURLFTPTransfer *transfer = [[CURLFTPTransfer alloc] initWithRequest:request session:self dataHandler:dataBlock completionHandler:^(CURLHandle *handle, NSError *error) {
            
            handler(handle, error);
        }];
        [transfer release];
    }];
}

- (void)sendRequest:(NSURLRequest *)request progressBlock:(void (^)(NSUInteger bytesWritten))progressBlock completionHandler:(void (^)(CURLHandle *handle, NSError *error))handler;
{
    [self doAuthThenPerformBlock:^{
        CURLFTPTransfer *transfer = [[CURLFTPTransfer alloc] initWithRequest:request session:self progressBlock:progressBlock completionHandler:^(CURLHandle *handle, NSError *error) {
            
            handler(handle, error);
        }];
        [transfer release];
    }];
}

#pragma mark NSURLAuthenticationChallengeSender

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    _credential = [credential copy];
    [_opsAwaitingAuth setSuspended:NO];
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [_opsAwaitingAuth setSuspended:NO];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [NSException raise:NSInvalidArgumentException format:@"Don't support cancelling FTP session auth yet"];
}

#pragma mark Home Directory

- (void)findHomeDirectoryWithCompletionHandler:(void (^)(NSString *path, NSError *error))handler;
{
    // Deliberately want a request that should avoid doing any work
    NSMutableURLRequest *request = [_request mutableCopy];
    [request setURL:[NSURL URLWithString:@"/" relativeToURL:[request URL]]];
    [request setHTTPMethod:@"HEAD"];
    
    [self sendRequest:request dataHandler:nil completionHandler:^(CURLHandle *handle, NSError *error) {
        if (error)
        {
            handler(nil, error);
        }
        else
        {
            handler([handle initialFTPPath], error);
        }
    }];
    
    [request release];
}

#pragma mark Discovering Directory Contents

- (void)enumerateContentsOfDirectoryAtPath:(NSString *)path usingBlock:(void (^)(NSDictionary *parsedResourceListing, NSError *error))block;
{
    if (!path) path = @".";
    NSMutableURLRequest *request = [self newMutableRequestWithPath:path isDirectory:YES];
    
    NSMutableData *totalData = [[NSMutableData alloc] init];
    
    [self sendRequest:request dataHandler:^(NSData *data) {
        [totalData appendData:data];
    } completionHandler:^(CURLHandle *handle, NSError *error) {
        
        if (error)
        {
            block(nil, error);
        }
        else
        {
            // Process the data to make a directory listing
            while (1)
            {
                CFDictionaryRef parsedDict = NULL;
                CFIndex bytesConsumed = CFFTPCreateParsedResourceListing(NULL,
                                                                         [totalData bytes], [totalData length],
                                                                         &parsedDict);
                
                if (bytesConsumed > 0)
                {
                    // Make sure CFFTPCreateParsedResourceListing was able to properly
                    // parse the incoming data
                    if (parsedDict)
                    {
                        block((NSDictionary *)parsedDict, nil);
                        CFRelease(parsedDict);
                    }
                    
                    [totalData replaceBytesInRange:NSMakeRange(0, bytesConsumed) withBytes:NULL length:0];
                }
                else if (bytesConsumed < 0)
                {
                    // error!
                    NSDictionary *userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
                                              [request URL], NSURLErrorFailingURLErrorKey,
                                              [[request URL] absoluteString], NSURLErrorFailingURLStringErrorKey,
                                              nil];
                    
                    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotParseResponse userInfo:userInfo];
                    [userInfo release];
                    
                    block(nil, error);
                    break;
                }
                else
                {
                    block(nil, nil);
                    break;
                }
            }
        }
    }];

    [request release];
}

#pragma mark Creating and Deleting Items

- (void)createFileAtPath:(NSString *)path contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    NSMutableURLRequest *request = [self newMutableRequestWithPath:path isDirectory:NO];
    [request setHTTPBody:data];
    [request curl_setCreateIntermediateDirectories:createIntermediates];
    
    [self createFileWithRequest:request progressBlock:progressBlock];
    [request release];
}

- (void)createFileAtPath:(NSString *)path withContentsOfURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    NSMutableURLRequest *request = [self newMutableRequestWithPath:path isDirectory:NO];
    
    // Read the data using an input stream if possible
    NSInputStream *stream = [[NSInputStream alloc] initWithURL:url];
    if (stream)
    {
        [request setHTTPBodyStream:stream];
        [stream release];
    }
    else
    {
        NSError *error;
        NSData *data = [[NSData alloc] initWithContentsOfURL:url options:0 error:&error];
        
        if (data)
        {
            [request setHTTPBody:data];
            [data release];
        }
        else
        {
            [request release];
            if (!error) error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
            progressBlock(0, error);
            return;
        }
    }
    
    [request curl_setCreateIntermediateDirectories:createIntermediates];
    
    [self createFileWithRequest:request progressBlock:progressBlock];
    [request release];
}

- (void)createFileWithRequest:(NSURLRequest *)request progressBlock:(void (^)(NSUInteger bytesWritten, NSError *error))progressBlock;
{
    // Use our own progress block to watch for the file end being reached before passing onto the original requester
    __block BOOL atEnd = NO;
    
    [self sendRequest:request progressBlock:^(NSUInteger bytesWritten) {
        
        if (bytesWritten == 0) atEnd = YES;
        if (bytesWritten && progressBlock) progressBlock(bytesWritten, nil);
        
    } completionHandler:^(CURLHandle *handle, NSError *error) {
        
        // Long FTP uploads have a tendency to have the control connection cutoff for idling. As a hack, assume that if we reached the end of the body stream, a timeout is likely because of that
        if (error && atEnd && [error code] == NSURLErrorTimedOut && [[error domain] isEqualToString:NSURLErrorDomain])
        {
            error = nil;
        }
        
        progressBlock(0, error);
    }];
}

- (void)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates completionHandler:(void (^)(NSError *error))handler;
{
    return [self executeCustomCommands:[NSArray arrayWithObject:[@"MKD " stringByAppendingString:[path lastPathComponent]]]
                           inDirectory:[path stringByDeletingLastPathComponent]
         createIntermediateDirectories:createIntermediates
                     completionHandler:handler];
}

- (void)setAttributes:(NSDictionary *)attributes ofItemAtPath:(NSString *)path completionHandler:(void (^)(NSError *error))handler;
{
    NSParameterAssert(attributes);
    NSParameterAssert(path);
    
    NSNumber *permissions = [attributes objectForKey:NSFilePosixPermissions];
    if (permissions)
    {
        NSArray *commands = [NSArray arrayWithObject:[NSString stringWithFormat:
                                                      @"SITE CHMOD %lo %@",
                                                      [permissions unsignedLongValue],
                                                      [path lastPathComponent]]];
        
        [self executeCustomCommands:commands
                        inDirectory:[path stringByDeletingLastPathComponent]
      createIntermediateDirectories:NO
                  completionHandler:handler];
        
        return;
    }
    
    handler(nil);
}

- (void)removeFileAtPath:(NSString *)path completionHandler:(void (^)(NSError *error))handler;
{
    return [self executeCustomCommands:[NSArray arrayWithObject:[@"DELE " stringByAppendingString:[path lastPathComponent]]]
                           inDirectory:[path stringByDeletingLastPathComponent]
         createIntermediateDirectories:NO
                     completionHandler:handler];
}

#pragma mark Cancellation

- (void)cancel; { /* FIXME: actually cancel something! */ }

#pragma mark Delegate

@synthesize delegate = _delegate;

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    // Don't want to include password in transcripts usually!
    if (type == CURLINFO_HEADER_OUT &&
        [string hasPrefix:@"PASS"] &&
        ![[NSUserDefaults standardUserDefaults] boolForKey:@"AllowPasswordToBeLogged"])
    {
        string = @"PASS ####";
    }
    
    [[self delegate] FTPSession:self didReceiveDebugInfo:string ofType:type];
}

#pragma mark FTP URL helpers

+ (NSURL *)URLWithPath:(NSString *)path relativeToURL:(NSURL *)baseURL;
{
    // FTP is special. Absolute paths need to specified with an extra prepended slash <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    NSString *scheme = [baseURL scheme];
    
    if (([@"ftp" caseInsensitiveCompare:scheme] == NSOrderedSame || [@"ftps" caseInsensitiveCompare:scheme] == NSOrderedSame) &&
        [path isAbsolutePath])
    {
        // Get to host's URL, including single trailing slash
        // -absoluteURL has to be called so that the real path can be properly appended
        baseURL = [[NSURL URLWithString:@"/" relativeToURL:baseURL] absoluteURL];
        return [baseURL URLByAppendingPathComponent:path];
    }
    else
    {
        return [NSURL URLWithString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
                      relativeToURL:baseURL];
    }
}

+ (NSString *)pathOfURLRelativeToHomeDirectory:(NSURL *)URL;
{
    // FTP is special. The first slash of the path is to be ignored <http://curl.haxx.se/libcurl/c/curl_easy_setopt.html#CURLOPTURL>
    NSString *scheme = [URL scheme];
    if ([@"ftp" caseInsensitiveCompare:scheme] == NSOrderedSame || [@"ftps" caseInsensitiveCompare:scheme] == NSOrderedSame)
    {
        CFStringRef strictPath = CFURLCopyStrictPath((CFURLRef)[URL absoluteURL], NULL);
        NSString *result = [(NSString *)strictPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (strictPath) CFRelease(strictPath);
        return result;
    }
    else
    {
        return [URL path];
    }
}

@end


#pragma mark -


@implementation CURLFTPTransfer

- (id)initWithRequest:(NSURLRequest *)request session:(CURLFTPSession *)session completionHandler:(void (^)(CURLHandle *, NSError *))handler;
{
    if (self = [self init])
    {
        [self retain];  // until finished
        _session = [session retain];
        _completionHandler = [handler copy];
        
        CURLHandle *handle = [[CURLHandle alloc] initWithRequest:request
                                                      credential:[session valueForKey:@"_credential"]   // dirty secret!
                                                        delegate:self];
        
        [handle release];   // handle retains itself until finished or cancelled
    }
    
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request session:(CURLFTPSession *)session dataHandler:(void (^)(NSData *))dataBlock completionHandler:(void (^)(CURLHandle *, NSError *))handler
{
    if (self = [self initWithRequest:request session:session completionHandler:handler])
    {
        _dataBlock = [dataBlock copy];
    }
    return self;
}

- (id)initWithRequest:(NSURLRequest *)request session:(CURLFTPSession *)session progressBlock:(void (^)(NSUInteger))progressBlock completionHandler:(void (^)(CURLHandle *, NSError *))handler
{
    if (self = [self initWithRequest:request session:session completionHandler:handler])
    {
        _progressBlock = [progressBlock copy];
    }
    return self;
}

- (void)handle:(CURLHandle *)handle didFailWithError:(NSError *)error;
{
    if (!error) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
    _completionHandler(handle, error);
    [self release];
}

- (void)handle:(CURLHandle *)handle didReceiveData:(NSData *)data;
{
    if (_dataBlock) _dataBlock(data);
}

- (void)handle:(CURLHandle *)handle willSendBodyDataOfLength:(NSUInteger)bytesWritten
{
    if (_progressBlock) _progressBlock(bytesWritten);
}

- (void)handleDidFinish:(CURLHandle *)handle;
{
    _completionHandler(handle, nil);
    [self release];
}

- (void)handle:(CURLHandle *)handle didReceiveDebugInformation:(NSString *)string ofType:(curl_infotype)type;
{
    [[_session delegate] FTPSession:_session didReceiveDebugInfo:string ofType:type];
}

- (void)dealloc;
{
    [_session release];
    [_completionHandler release];
    [_dataBlock release];
    [_progressBlock release];
    
    [super dealloc];
}

@end
