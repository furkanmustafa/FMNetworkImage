//
//  FMNetworkImage.h
//
//  Created by Furkan Mustafa on 9/17/13.
//

#import <UIKit/UIKit.h>

@interface FMNetworkImage : UIImageView

- (void)setImageURL:(NSURL *)imageURL target:(id)target success:(SEL)success failure:(SEL)failure;
- (void)setImageURL:(NSURL *)imageURL completionBlock:(void (^)(UIImage * image))onLoad;
- (void)cancelLoading;

+ (UIImage*)cachedImageForURL:(NSURL *)imageURL;

@property (nonatomic, retain) UIImage* placeholderImage;
@property (atomic, retain) UIImage* imageToDecompress;
@property (nonatomic, readwrite) UIViewContentMode placeholderContentMode;
@property (nonatomic, readwrite) UIViewContentMode loadedImageContentMode;

@property (nonatomic, retain) NSURL* imageURL;
@property (nonatomic, assign) id completetionTarget;
@property (nonatomic, assign) SEL completetionSelector;
@property (nonatomic, assign) SEL failureSelector;
@property (nonatomic, assign) CGFloat imageScale;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, retain) NSDate* startedLoadingAt;
@property (nonatomic, assign) NSTimeInterval loadingTook;

@property (nonatomic, assign) BOOL crossfadeImages;
@property (nonatomic, assign) NSTimeInterval delayBeforeLoading;
@property (nonatomic, copy) void (^onLoad) (UIImage* image);

@property (atomic,retain) NSURLConnection* conn;
@property (atomic,retain) NSMutableData* data;

@end

