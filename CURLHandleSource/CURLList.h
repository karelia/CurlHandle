//
//  CURLList.h
//  CURLHandle
//
//  Created by Sam Deane on 28/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CURLList : NSObject
{
    struct curl_slist* _list;
}

@property (readonly, nonatomic) struct curl_slist* list;

+ (CURLList*)listWithContentsOfArray:(NSArray*)array;
+ (CURLList*)listWithString:(NSString*)string;

- (void)appendString:(NSString*)string;

@end
