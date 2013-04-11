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
 
 You can make a list from an array or a single object, using listWithContentsOrArray: or listWithString:.
 You can then append items to it with appendObject:
 
 There is no way to remove or re-order items, and the only way to empty it is to release it.
 
 The curl_slist type is only designed to contain strings. When you add something to CURLList,
 it calls description on it to get a textual representation.
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
 Create a list from an array of objects.
 
 We will call [NSObject description] on each object to obtain a textual representation, which is what will actually be added to the list.

 @param array The items for the list - must contain only NSString objects.
 @return The new list.
 */

+ (CURLList*)listWithArray:(NSArray*)array;

/**
 Create a list with a single object.
 
 We will call [NSObject description] on the object to obtain a textual representation, which is what will actually be added to the list.

 @param object An object to add to the new list.
 @return The new list.
 */

+ (CURLList*)listWithObject:(id<NSObject>)object;

/**
 Add an object to the list.
 
 We will call [NSObject description] on the object to obtain a textual representation, which is what will actually be added to the list.

 @param object The object to add.
*/

- (void)addObject:(id<NSObject>)object;

@end
