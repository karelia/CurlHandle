//
//  NSString+CURLHandle.m
//  CURLHandle
//
//  Created by Dan Wood <dwood@karelia.com> on Fri Jun 22 2001.
//  Copyright (c) 2013 Karelia Software. All rights reserved.

#import "NSString+CURLHandle.h"

@implementation NSString (CURLHandle)

- (NSString *) headerStatus
{
	// Get the first line of the headers
	NSArray *components = [self componentsSeparatedByLineSeparators];
	NSString *theFirstLine = [components objectAtIndex:0];
	// Pull out from the second "word"
	NSArray *theLineComponents = [theFirstLine componentsSeparatedByString: @" "];
	NSRange theRange = NSMakeRange(2, [theLineComponents count] - 2);
	NSString *theResult = [[theLineComponents subarrayWithRange: theRange] componentsJoinedByString: @" "];
	return theResult;
}

- (NSString *) headerHTTPVersion
{
	NSString *result = nil;
	// Get the first "word" of the first line of the headers
	NSRange whereSpace = [self rangeOfString:@" "];
	if (NSNotFound != whereSpace.location)
	{
		result = [self substringToIndex:whereSpace.location];
	}
	return result;
}

/*"	Create an array of values from the HTTP headers string that match the given header key.
"*/

- (NSArray *) headersMatchingKey:(NSString *)inKey
{
	NSMutableArray *result = [NSMutableArray array];
	NSArray *components = [self componentsSeparatedByLineSeparators];
	NSEnumerator *theEnum = [components objectEnumerator];
	NSString *theLine = [theEnum nextObject];		// result code -- ignore
	(void)theLine;
	while (nil != (theLine = [theEnum nextObject]) )
	{
		if ([[theLine headerKey] isEqualToString:inKey])
		{
			// Add it to the resulting array
			[result addObject:[theLine headerValue]];
		}
	}
	return result;
}


/*" Return a the single (first) value of a header.  Returns NULL if not found. "*/

- (NSString *)headerMatchingKey:(NSString *)inKey
{
	NSString *result = nil;
	NSArray *headerArray = [self headersMatchingKey:inKey];
	if ([headerArray count] > 0)
	{
		result = [headerArray objectAtIndex:0];
	}
	return result;
}


/*"	Create a dictionary from the HTTP headers. "*/

- (NSDictionary *) allHTTPHeaderFields;
{
	NSArray *components = [self componentsSeparatedByLineSeparators];
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[components count] - 1];
	
	NSEnumerator *theEnum = [components objectEnumerator];
	NSString *theLine = [theEnum nextObject];		// result code -- ignore
	(void)theLine;
	while (nil != (theLine = [theEnum nextObject]) )
	{
		NSString *key = [theLine headerKey];
		NSString *value = [theLine headerValue];
		if (nil != key && nil != value)
		{
			// Add a single dictionary for this header name/value
			[result setObject:value forKey:key];
		}
	}
	return result;
}

/*" Given a line of a header, e.g. "Foo: Bar" "*/

- (NSString *) headerKey
{
	NSString *result = nil;
	NSRange whereColon = [self rangeOfString:@": "];
	if (NSNotFound != whereColon.location)
	{
		result = [self substringToIndex:whereColon.location];
	}
	return result;
}

/*" Given a line of a header, e.g. "Foo: Bar", return the value in lowercase form, e.g. "bar". "*/

- (NSString *) headerValue
{
	NSString *result = nil;
	NSRange whereColon = [self rangeOfString:@": "];
	if (NSNotFound != whereColon.location)
	{
		result = [self substringFromIndex:whereColon.location + 2];
	}
	return result;
}


/*"	Split a string into lines separated by any of the various newline characters.  Equivalent to componentsSeparatedByString:@"\n" but it works with the different line separators: \r, \n, \r\n, 0x2028, 0x2029 "*/

- (NSArray *) componentsSeparatedByLineSeparators
{
	NSMutableArray *result	= [NSMutableArray array];
	NSRange range = NSMakeRange(0,0);
	NSUInteger start, end;
	NSUInteger contentsEnd = 0;
	
	while (contentsEnd < [self length])
	{
		[self getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:range];
		[result addObject:[self substringWithRange:NSMakeRange(start,contentsEnd-start)]];
		range.location = end;
		range.length = 0;
	}
	return result;
}
@end
