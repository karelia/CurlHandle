//
//  CURLSocketRegistration.h
//  CURLHandle
//
//  Created by Sam Deane on 26/09/2012.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CURLMultiHandle;

/**
 * Internal wrapper for dispatch sources that monitor each of the curl sockets.
 * CURLMulti uses this internally - not intended for public consumption.
 */

@interface CURLSocketRegistration : NSObject
{
    dispatch_source_t _reader;
    dispatch_source_t _writer;
}

/**
 * Create/destroy the dispatch sources, based on the values in the mode parameter.
 * CURLMulti uses this internally - not intended for public consumption.
 *
 * @param socket The socket .
 * @param mode Whether we are interested in reads, writes, or both.
 * @param multi The multi that this object is working with.
 */

- (void)updateSourcesForSocket:(int)socket mode:(int)mode multi:(CURLMultiHandle*)multi;

/**
 Indicates whether a given source is owned by this socket.

 @param source The source to check.
 @return Returns YES if the source is owned by this socket.
 */

- (BOOL)ownsSource:(dispatch_source_t)source;

@end
