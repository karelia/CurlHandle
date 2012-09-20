//
//  CURLRunLoopSource.h
//  CURLHandle
//
//  Created by Sam Deane on 20/09/2012.
//
//

#import <Foundation/Foundation.h>

@class CURLHandle;

@interface CURLRunLoopSource : NSObject

- (id)init;

- (void)addToRunLoop:(NSRunLoop*)runLoop;
- (void)removeFromRunLoop:(NSRunLoop*)runLoop;

- (void)addToRunLoop:(NSRunLoop*)runLoop mode:(NSString*)mode;
- (void)removeFromRunLoop:(NSRunLoop*)runLoop mode:(NSString*)mode;

- (BOOL)addHandle:(CURLHandle*)handle;
- (BOOL)removeHandle:(CURLHandle*)handle;

- (void)shutdown;

@end
