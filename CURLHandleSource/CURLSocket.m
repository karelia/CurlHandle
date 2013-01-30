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
@property (assign, nonatomic) int socket; // TODO: this is only needed for debugging - could remove eventually

@end

@implementation CURLSocket

#pragma mark - Synthesized Properties

@synthesize reader = _reader;
@synthesize writer = _writer;
@synthesize socket = _socket;

#pragma mark - Implementation

- (id)initWithSocket:(int)socket
{
    if ((self = [super init]) != nil)
    {
        self.socket = socket;
    }

    return self;
}

- (void)updateSourcesForSocket:(int)socket mode:(NSInteger)mode multi:(CURLMulti*)multi
{
    // We call back to the multi to do the actual work - this class really just exists as
    // a place to group together the reader and writer sources corresponding to a socket.

    self.socket = socket; // for debug purposes only

    BOOL readerRequired = (mode == CURL_POLL_IN) || (mode == CURL_POLL_INOUT);
    self.reader = [multi updateSource:self.reader type:DISPATCH_SOURCE_TYPE_READ socket:socket required:readerRequired];

    BOOL writerRequired = (mode == CURL_POLL_OUT) || (mode == CURL_POLL_INOUT);
    self.writer = [multi updateSource:self.writer type:DISPATCH_SOURCE_TYPE_WRITE socket:socket required:writerRequired];
}

- (NSString*)description
{
    NSString* mode = self.reader ? (self.writer ? @" reading writing" : @" reading") : (self.writer ? @" writing" : @"");
    return [NSString stringWithFormat:@"<%d%@>", self.socket, mode];
}

@end
