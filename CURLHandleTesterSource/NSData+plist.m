 
//
//  NSData+plist.m
//
//

// Courtesy of Ken Dyke.
// See "What is the easiest way to get an XML Plist into an NSDictionary?" on macosx-dev@omnigroup.com
//
//	Similar to [NSDictionary dictionaryWithContentsOfFile:path] but uses text as the input.

#import "NSData+plist.h"

@implementation NSData(nsObjectNSDataExtensions)

- (id)propertyListFromXMLWithOptions:(CFPropertyListMutabilityOptions)options
{
	CFPropertyListRef pList;
	CFStringRef errorString = nil;

	pList = CFPropertyListCreateFromXMLData(NULL, (CFDataRef)self, options, &errorString);
	
	// Error if string, or if the pList is actually NOT a dictionary, but is instead a STRING!
	if(errorString)
	{
NSLog(@"Error loading from Property List:%@",(NSString*)errorString);
		CFRelease(errorString);
	}
	if (![(id)pList isKindOfClass:[NSDictionary class]])
	{
NSLog(@"Error loading from Property List -- result is not a dictionary");
		[(id)pList release];
		return nil;
	}
	return [(id)pList autorelease];
}

- (id)propertyListFromXML
{
	return [self propertyListFromXMLWithOptions:kCFPropertyListImmutable];
}

- (id)mutablePropertyListFromXML
{
	return [self propertyListFromXMLWithOptions:kCFPropertyListMutableContainersAndLeaves];
}

@end
