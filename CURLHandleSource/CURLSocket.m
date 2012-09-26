//
//  CURLSocket.m
//  CURLHandle
//
//  Created by Sam Deane on 26/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLSocket.h"
#import "CURLMulti.h"

#import <curl/curl.h>

@implementation CURLSocket

- (void)updateSourcesForSocket:(int)socket mode:(NSInteger)mode multi:(CURLMulti*)multi
{
    BOOL readerRequired = (mode == CURL_POLL_IN) || (mode == CURL_POLL_INOUT);
    self.reader = [multi updateSource:self.reader type:DISPATCH_SOURCE_TYPE_READ socket:socket required:readerRequired];

    BOOL writerRequired = (mode == CURL_POLL_OUT) || (mode == CURL_POLL_INOUT);
    self.writer = [multi updateSource:self.writer type:DISPATCH_SOURCE_TYPE_WRITE socket:socket required:writerRequired];
}

@end
