//
//  CURLSocket.m
//  CURLHandle
//
//  Created by Sam Deane on 26/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import "CURLSocket.h"

#import "CURLHandle.h"

@implementation CURLSocket

- (void)updateSourcesForSocket:(int)socket mode:(NSInteger)mode multi:(CURLM*)multi queue:(dispatch_queue_t)queue
{
    if ((mode == CURL_POLL_IN) || (mode == CURL_POLL_INOUT))
    {
        if (!self.reader)
        {
            CURLHandleLog(@"added reader for socket %d", socket);
            self.reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, socket, 0, queue);
            dispatch_source_set_event_handler(self.reader, ^{
                CURLHandleLog(@"socket %d ready to read", socket);
                int running;
                curl_multi_socket_action(multi, socket, CURL_CSELECT_IN, &running);
            });
            dispatch_resume(self.reader);
        }
    }
    else if (self.reader)
    {
        dispatch_release(self.reader);
        self.reader = nil;
        CURLHandleLog(@"removed reader for socket %d", socket);
    }

    if ((mode == CURL_POLL_OUT) || (mode == CURL_POLL_INOUT))
    {
        if (!self.writer)
        {
            CURLHandleLog(@"added writer for socket %d", socket);
            self.writer = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, socket, 0, queue);
            dispatch_source_set_event_handler(self.writer, ^{
                CURLHandleLog(@"socket %d ready to write", socket);
                int running;
                curl_multi_socket_action(multi, socket, CURL_CSELECT_OUT, &running);
            });
            dispatch_resume(self.writer);
        }
    }
    else if (self.writer)
    {
        dispatch_release(self.writer);
        self.writer = nil;
        CURLHandleLog(@"removed writer for socket %d", socket);
    }

}

@end
