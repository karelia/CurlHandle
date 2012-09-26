//
//  CURLSocket.h
//  CURLHandle
//
//  Created by Sam Deane on 26/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <curl/curl.h>

@interface CURLSocket : NSObject

@property (assign, nonatomic) dispatch_source_t reader;
@property (assign, nonatomic) dispatch_source_t writer;

- (void)updateSourcesForSocket:(int)socket mode:(NSInteger)mode multi:(CURLM*)multi queue:(dispatch_queue_t)queue;

@end
