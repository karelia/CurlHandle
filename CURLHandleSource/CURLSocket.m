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

@interface CURLSocket()

#pragma mark - Private Properties

@property (assign, nonatomic) dispatch_source_t reader;
@property (assign, nonatomic) dispatch_source_t writer;

@end

@implementation CURLSocket

#pragma mark - Synthesized Properties

@synthesize reader = _reader;
@synthesize writer = _writer;

#pragma mark - Implementation

- (void)dealloc
{
    if (self.reader)
    {
        dispatch_source_cancel(self.reader); // the cancel handler will release the source
    }

    if (self.writer)
    {
        dispatch_source_cancel(self.writer); // the cancel handler will release the source
    }

    [super dealloc];
}

- (void)updateSourcesForSocket:(int)socket mode:(NSInteger)mode multi:(CURLMulti*)multi
{
    // We call back to the multi to do the actual work - this class really just exists as
    // a place to group together the reader and writer sources corresponding to a socket.

    BOOL readerRequired = (mode == CURL_POLL_IN) || (mode == CURL_POLL_INOUT);
    self.reader = [multi updateSource:self.reader type:DISPATCH_SOURCE_TYPE_READ socket:self raw:socket required:readerRequired];

    BOOL writerRequired = (mode == CURL_POLL_OUT) || (mode == CURL_POLL_INOUT);
    self.writer = [multi updateSource:self.writer type:DISPATCH_SOURCE_TYPE_WRITE socket:self raw:socket required:writerRequired];
}

- (NSString*)description
{
    NSString* mode;
    if (self.reader)
    {
        if (self.writer)
        {
            mode = [NSString stringWithFormat:@"read, write sources for %lu", dispatch_source_get_handle(self.reader)];
        }
        else
        {
            mode = [NSString stringWithFormat:@"read source for %lu", dispatch_source_get_handle(self.reader)];
        }
    }
    else if (self.writer)
    {
        mode = [NSString stringWithFormat:@"write source for %lu", dispatch_source_get_handle(self.writer)];
    }
    else
    {
        mode = @"no sources";
    }

    return [NSString stringWithFormat:@"<socket %p %@>", self, mode];
}

- (BOOL)ownsSource:(dispatch_source_t)source
{
    return (self.reader == source) || (self.writer == source);
}

@end
