//
//  CURLRunLoopSource.h
//  CURLHandle
//
//  Created by Sam Deane on 20/09/2012.
//
//

#import <Foundation/Foundation.h>

#import <curl/curl.h>

@class CURLHandle;

@interface CURLRunLoopSource : NSObject
{
    CFRunLoopSourceRef _source;
    NSThread* _thread;
    CURLM* _multi;
    BOOL _handleAdded;
    NSMutableArray* _handles;
    struct timeval _timeout;

}
- (id)init;

- (void)addToRunLoop:(NSRunLoop*)runLoop;
- (void)removeFromRunLoop:(NSRunLoop*)runLoop;

- (void)addToRunLoop:(NSRunLoop*)runLoop mode:(NSString*)mode;
- (void)removeFromRunLoop:(NSRunLoop*)runLoop mode:(NSString*)mode;

- (BOOL)addHandle:(CURLHandle*)handle;
- (BOOL)removeHandle:(CURLHandle*)handle;

- (void)shutdown;

@end
