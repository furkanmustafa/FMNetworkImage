//
//  AppDelegate.m
//  NetworkImageTest
//
//  Created by Furkan Mustafa on 10/9/13.
//  Copyright (c) 2013 fume. All rights reserved.
//

#import "AppDelegate.h"
#import "ImageCollection.h"

@implementation AppDelegate

- (void)dealloc {
    self.window = nil;
	[super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	
	self.window = [[UIWindow.alloc initWithFrame:UIScreen.mainScreen.bounds] autorelease];
	
	self.window.rootViewController = ImageCollection.new.autorelease;
	[self.window makeKeyAndVisible];

	NSLog(@"Launched..");
    return YES;
}

@end
