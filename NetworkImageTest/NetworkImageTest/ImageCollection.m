//
//  ImageCollection.m
//  NetworkImageTest
//
//  Created by Furkan Mustafa on 10/12/13.
//  Copyright (c) 2013 fume. All rights reserved.
//

#import "ImageCollection.h"
#import "UIImageView+FMNetworkImage.h"

@interface ImageCollection ()

@end

NSString* const ImageCollectionCell_ReuseIdentifier = @"ImageCollectionCell";

@interface ImageCollectionCell : UICollectionViewCell {
	UIImageView* imageView;
}

@property (nonatomic, retain) NSURL* imageURL;

@end

@implementation ImageCollection

- (id)init {
    self = [super init];
    if (self) {
        // Custom initialization

    }
    return self;
}

- (void)loadView {
	self.view = [UIView.alloc initWithFrame:UIScreen.mainScreen.bounds].autorelease;
	self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight + UIViewAutoresizingFlexibleWidth;
	self.view.backgroundColor = [UIColor colorWithWhite:.1 alpha:1];
	
	UICollectionViewFlowLayout* layout = [UICollectionViewFlowLayout.new autorelease];
	if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		layout.itemSize = CGSizeMake(200, 200);
		layout.minimumInteritemSpacing = 20.0;
		layout.minimumLineSpacing = 20.0;
		layout.sectionInset = UIEdgeInsetsMake(20, 20, 20, 20);
	} else {
		layout.itemSize = CGSizeMake(145, 145);
		layout.minimumInteritemSpacing = 10.0;
		layout.minimumLineSpacing = 10.0;
		layout.sectionInset = UIEdgeInsetsMake(10, 10, 10, 10);
	}
	self.collectionView = [UICollectionView.alloc initWithFrame:self.view.bounds collectionViewLayout:layout].autorelease;
	[self.view addSubview:self.collectionView];
//	self.collectionView.
	self.collectionView.delegate = self;
	self.collectionView.dataSource = self;
	[self.collectionView registerClass:ImageCollectionCell.class forCellWithReuseIdentifier:ImageCollectionCell_ReuseIdentifier];
}

- (void)viewDidLoad {
    [self loadFile];
}
- (void)loadFile {
	self.imageURLs = NSMutableArray.array;
	NSString* urlsFilePath = [[NSBundle mainBundle] pathForResource:@"urls" ofType:@"txt"];
	NSString* urlsFileContent = [NSString stringWithContentsOfFile:urlsFilePath encoding:NSUTF8StringEncoding error:nil];
	NSArray* urls = [urlsFileContent componentsSeparatedByString:@"\n"];
	for (NSString* aUrl in urls) {
		if (aUrl.length > 5)
			[self.imageURLs addObject:aUrl];
	}
	NSLog(@"Loaded %lu images", (unsigned long)self.imageURLs.count);
	[self.collectionView reloadData];
}

#pragma mark - CollectionView
#pragma mark -

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.imageURLs.count;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	ImageCollectionCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier:ImageCollectionCell_ReuseIdentifier forIndexPath:indexPath];
	
	cell.imageURL = [NSURL URLWithString:[self.imageURLs objectAtIndex:indexPath.item]];
	
	return (id)cell;
}

//- (void)removeCells {
//	self.collectionView.dataSource = nil;
//	self.collectionView.delegate = nil;
//	[self.collectionView removeFromSuperview];
//	self.collectionView = nil;
//}
//
//- (void)viewDidAppear:(BOOL)animated {
//	// memory release test
//	[self performSelector:@selector(removeCells) withObject:nil afterDelay:5.0];
//}

@end

@implementation ImageCollectionCell

- (void)dealloc {
	self.imageURL = nil;
	[super dealloc];
}

- (void)prepareForReuse {
	imageView.netImage.URL = nil;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
 		self.backgroundColor = UIColor.whiteColor;
		self.autoresizesSubviews = YES;

        imageView = [UIImageView.alloc initWithFrame:CGRectInset(self.bounds, 10, 10)].autorelease;
		imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth + UIViewAutoresizingFlexibleHeight;
		imageView.backgroundColor = UIColor.lightGrayColor;
		imageView.netImage.placeholderImage = [UIImage imageNamed:@"placeholder.png"];
		imageView.netImage.placeholderContentMode = UIViewContentModeCenter;
		imageView.netImage.loadedImageContentMode = UIViewContentModeScaleAspectFill;
		imageView.netImage.crossfadeImages = YES;
		imageView.netImage.delayBeforeLoading = 1.0 / 30.0;
		imageView.netImage.fixImageCropResize = YES;
		imageView.netImage.cacheDecodedResults = YES;
		imageView.clipsToBounds = YES;
		
		[self addSubview:imageView];
   }
    return self;
}

- (void)setImageURL:(NSURL *)imageURL {
	imageView.netImage.URL = imageURL;
}

@end

