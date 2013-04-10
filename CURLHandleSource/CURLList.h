//
//  CURLList.h
//  CURLHandle
//
//  Created by Sam Deane on 28/03/2013.
//  Copyright (c) 2013 Karelia Software. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 Wrapper for the curl_slist structure.
 
 You can make a list from an array or a single string, using listWithContentsOrArray: or listWithString:.
 You can then append items to it with appendString:
 
 There is no way to remove or re-order items, and the only way to empty it is to release it.
 */

@interface CURLList : NSObject
{
    struct curl_slist* _list;
}

/**
 The underlying curl_slist structure.
 */

@property (readonly, nonatomic) struct curl_slist* list;

/**
 Create a list from an array of strings.
 
 @param array The items for the list - must contain only NSString objects.
 @return The new list.
 */

+ (CURLList*)listWithContentsOfArray:(NSArray*)array;

/**
 Create a list with a single string.
 
 @param string A string to add to the new list.
 @return The new list.
 */

+ (CURLList*)listWithString:(NSString*)string;

/**
 Append a string to the list.
 
 @param string The string to append.
*/

- (void)appendString:(NSString*)string;

@end
