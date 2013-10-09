//
//  ViewController.m
//  NetworkImageTest
//
//  Created by Furkan Mustafa on 10/9/13.
//  Copyright (c) 2013 fume. All rights reserved.
//

#import "ViewController.h"
#import "FMNetworkImage.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	FMNetworkImage* networkImage = [FMNetworkImage.alloc initWithFrame:CGRectInset(self.view.bounds, 30, 30)].autorelease;
	networkImage.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
	
	networkImage.clipsToBounds = YES;
	networkImage.backgroundColor = UIColor.darkGrayColor;
	
	networkImage.loadedImageContentMode = UIViewContentModeScaleAspectFill;
	networkImage.imageURL = [NSURL URLWithString:@"http://fume.jp/test/beach.jpg"];
	
	[self.view addSubview:networkImage];
	
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
