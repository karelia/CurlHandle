#import <Foundation/Foundation.h>

// Courtesy of Ken Dyke.
// See "What is the easiest way to get an XML Plist into an NSDictionary?" on macosx-dev@omnigroup.com

@interface NSData(nsObjectNSDataExtensions)

// Go from XML to property list
- (id)propertyListFromXMLWithOptions:(CFPropertyListMutabilityOptions)options;
- (id)propertyListFromXML;
- (id)mutablePropertyListFromXML;

@end
