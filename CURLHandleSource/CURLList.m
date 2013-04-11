//
//  CURLList.m
//  CURLHandle
//
//  Created by Sam Deane on 28/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import "CURLList.h"

#import <curl/curl.h>

@implementation CURLList

@synthesize list = _list;

+ (CURLList*)listWithArray:(NSArray *)array
{
    CURLList* list = [[CURLList alloc] init];
    for (id<NSObject> object in array)
    {
        [list addObject:object];
    }

    return [list autorelease];
}

+ (CURLList*)listWithObject:(id<NSObject>)object
{
    CURLList* list = [[CURLList alloc] init];
    [list addObject:object];

    return [list autorelease];
}

- (void)addObject:(id<NSObject>)object
{
    _list = curl_slist_append(_list, [[object description] UTF8String]);
}

- (void)dealloc
{
    if (_list)
    {
        curl_slist_free_all(_list);
    }

    [super dealloc];
}

@end
