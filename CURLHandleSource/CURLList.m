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

+ (CURLList*)listWithContentsOfArray:(NSArray *)array
{
    CURLList* list = [[CURLList alloc] init];
    for (NSString* string in array)
    {
        [list appendString:string];
    }

    return [list autorelease];
}

+ (CURLList*)listWithString:(NSString *)string
{
    CURLList* list = [[CURLList alloc] init];
    [list appendString:string];

    return [list autorelease];
}

- (void)appendString:(NSString *)string
{
    _list = curl_slist_append(_list, [string UTF8String]);
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
