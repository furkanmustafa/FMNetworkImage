//
//  UIImageView+FMNetworkImage.h
//
//  Created by Furkan Mustafa on 10/12/13.
//

#import <Foundation/Foundation.h>

@class FMNetworkImage;

@interface UIImageView (FMNetworkImageCategory)
@property (nonatomic, retain) FMNetworkImage* netImage;
//LEGACY URL PROPERTY
@property (nonatomic, retain) NSURL* imageURL;
@end

typedef NS_ENUM(NSUInteger, FMNetworkImageStatus) {
	FMNetworkImageStatus_Idle = 0,
	FMNetworkImageStatus_PriorDelay,
	FMNetworkImageStatus_RemoteFetch,
	FMNetworkImageStatus_Convert,
	FMNetworkImageStatus_Decode,
	FMNetworkImageStatus_Loaded
};

@interface FMNetworkImage : NSObject {
	@private
	BOOL _loadingFromCacheDontFade;
}

+ (UIImage*)cachedImageForURL:(NSURL *)imageURL;
- (void)setURL:(NSURL *)URL target:(id)target success:(SEL)success failure:(SEL)failure;
- (void)setURL:(NSURL *)URL completionBlock:(void (^)(UIImage * image))onLoad;
- (void)cancelLoading;

@property (readonly) FMNetworkImageStatus status;

@property (nonatomic, retain) UIImage* placeholderImage;
@property (atomic, retain) UIImage* rawRemoteImage;
@property (nonatomic, readwrite) UIViewContentMode placeholderContentMode;
@property (nonatomic, readwrite) UIViewContentMode loadedImageContentMode;

@property (nonatomic, retain) NSURL* URL;
@property (nonatomic, assign) id completetionTarget;
@property (nonatomic, assign) SEL completetionSelector;
@property (nonatomic, assign) SEL failureSelector;
@property (nonatomic, assign) CGFloat imageScale;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, retain) NSDate* startedLoadingAt;
@property (nonatomic, assign) NSTimeInterval loadingTook;

@property (nonatomic, assign) BOOL crossfadeImages;
@property (nonatomic, assign) BOOL fixImageCropResize; // improves performance, not finished yet
@property (nonatomic, assign) NSTimeInterval delayBeforeLoading;
@property (nonatomic, copy) void (^onLoad) (UIImage* image);

@property (atomic,retain) NSURLConnection* conn;
@property (atomic,retain) NSMutableData* data;

@property (atomic, assign) UIImageView* imageView;

@property (nonatomic,retain) NSOperationQueue* queue;

@end
