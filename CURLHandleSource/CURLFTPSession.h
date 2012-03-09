//
//  CURLFTPSession.h
//  CURLHandle
//
//  Created by Mike Abdullah on 04/03/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import <CURLHandle/CURLHandle.h>


@protocol CURLFTPSessionDelegate;


@interface CURLFTPSession : NSObject <CURLHandleDelegate>
{
  @private
    CURLHandle          *_handle;
    NSURLRequest        *_request;
    NSURLCredential     *_credential;
    
    id <CURLFTPSessionDelegate> _delegate;
    
    NSMutableData   *_data;
}

// Returns nil if not a supported FTP URL
// All paths passed to a session are resolved relative to this request's URL. Normally you pass in a URL like ftp://example.com/ so it doesn't really make a difference! But let's say you passed in ftp://example.com/foo/ , a path of @"bar.html" would end up working on the file at ftp://example.com/foo/bar.html (i.e. the path foo/bar.html from the user's home directory)
- (id)initWithRequest:(NSURLRequest *)request;

- (void)useCredential:(NSURLCredential *)credential;

- (NSString *)homeDirectoryPath;


#pragma mark Discovering Directory Contents

- (NSArray *)contentsOfDirectory:(NSString *)path error:(NSError **)error;

// like -contentsOfDirectory:error: but returns an array of dictionaries, with keys like kCFFTPResourceName
- (NSArray *)parsedResourceListingsOfDirectory:(NSString *)path error:(NSError **)error;


#pragma mark Creating and Deleting Items

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data withIntermediateDirectories:(BOOL)createIntermediates error:(NSError **)error;

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates error:(NSError **)error;

- (BOOL)removeFileAtPath:(NSString *)path error:(NSError **)error;


#pragma mark Setting Attributes
// Only NSFilePosixPermissions is recognised at present. Note that some servers don't support this so will return an error (code 500)
// All other attributes are ignored
- (BOOL)setAttributes:(NSDictionary *)attributes ofItemAtPath:(NSString *)path error:(NSError **)error;


#pragma mark Delegate
@property(nonatomic, assign) id <CURLFTPSessionDelegate> delegate;


@end


@protocol CURLFTPSessionDelegate <NSObject>
- (void)FTPSession:(CURLFTPSession *)session didReceiveDebugInfo:(NSString *)info ofType:(curl_infotype)type;
@end