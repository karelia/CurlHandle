//
//  CURLSocket.h
//
//  Created by Sam Deane on 26/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CURLMulti;

/**
 * Internal wrapper for dispatch sources that monitor each of the curl sockets.
 * CURLMulti uses this internally - not intended for public consumption.
 */

@interface CURLSocket : NSObject
{
    int _socket;
    dispatch_source_t _reader;
    dispatch_source_t _writer;
}

- (id)initWithSocket:(int)socket;

/**
 * Create/destroy the dispatch sources, based on the values in the mode parameter.
 * CURLMulti uses this internally - not intended for public consumption.
 *
 * @param socket The raw socket.
 * @param mode Whether we are interested in reads, writes, or both.
 * @param multi The multi that this object is working with.
 */

- (void)updateSourcesForSocket:(int)socket mode:(NSInteger)mode multi:(CURLMulti*)multi;

@end
