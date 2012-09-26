//
//  CURLSocket.h
//  CURLHandle
//
//  Created by Sam Deane on 26/09/2012.
//  Copyright (c) 2012 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CURLMulti;

@interface CURLSocket : NSObject
{
    dispatch_source_t _reader;
    dispatch_source_t _writer;
}

- (void)updateSourcesForSocket:(int)socket mode:(NSInteger)mode multi:(CURLMulti*)multi;

@end
