//
//  FMNetworkImage.m
//
//  Created by Furkan Mustafa on 9/17/13.
//

#import "FMNetworkImage.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach_time.h>

@interface FMNetworkImage (NSURLConnection) <NSURLConnectionDelegate,NSURLConnectionDataDelegate>
- (void)processData;
@end

@interface FMNetworkImageOperation : NSOperation
@property (nonatomic,assign) id owner;
@property (nonatomic,assign) id target;
@property (nonatomic,assign) SEL selector;
@property (nonatomic,copy) id parameter;
+ (FMNetworkImageOperation*)operationWithOwner:(id)owner selector:(SEL)selector;
+ (FMNetworkImageOperation*)operationWithOwner:(id)owner target:(id)target selector:(SEL)selector;
+ (FMNetworkImageOperation*)currentOperation;
@end

@implementation FMNetworkImage

// Operation queue for downloading, processing and decoding images
+ (NSOperationQueue*)operationQueue {
	static NSOperationQueue* queue;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		queue = [NSOperationQueue new];
		queue.name = @"FMNetworkImage Queue";
	});
	return queue;
}
- (void)schedule:(SEL)selector {
	[self.class.operationQueue addOperation:[FMNetworkImageOperation operationWithOwner:self selector:selector]];
}
- (void)schedule:(SEL)selector withObject:(id)object {
	FMNetworkImageOperation* op = [FMNetworkImageOperation operationWithOwner:self selector:selector];
	op.parameter = object;
	[self.class.operationQueue addOperation:op];
}
- (void)schedule:(SEL)selector on:(id)target {
	[self.class.operationQueue addOperation:[FMNetworkImageOperation operationWithOwner:self target:target selector:selector]];
}
- (void)stopQueue {
	for (FMNetworkImageOperation* operation in [self.class.operationQueue.operations.copy autorelease]) {
		if ([operation isKindOfClass:FMNetworkImageOperation.class] && operation.owner==self)
			[operation cancel];
	}
}

- (void)dealloc {
	[self stopQueue];
	self.imageURL = nil;
	self.onLoad = nil;
	self.imageToDecompress = nil;
	self.startedLoadingAt = nil;
	self.conn = nil;
	self.data = nil;
	[super dealloc];
}
- (void)setImageURL:(NSURL *)imageURL target:(id)target success:(SEL)success failure:(SEL)failure {
	self.completetionTarget = target;
	self.completetionSelector = success;
	self.failureSelector = failure;
	self.imageURL = imageURL;
}
- (void)setImageURL:(NSURL *)imageURL completionBlock:(void (^)(UIImage * image))onLoad {
	self.onLoad = onLoad;
	self.imageURL = imageURL;
}
- (void)setImageURL:(NSURL *)imageURL {
	if (imageURL==_imageURL || (_imageURL && imageURL && [imageURL.absoluteString isEqualToString:_imageURL.absoluteString])) return;
	if (!imageURL) {
		[self cancelLoading];
	} else {
		[_imageURL autorelease]; _imageURL = [imageURL retain];
		[self initiateLoad:imageURL];
	}
}

#pragma mark - Callbacks on Main Thread

- (void)doneLoadingImage:(UIImage*)image {
	[self doneLoadingImage:image error:nil];
}
- (void)doneLoadingImage:(UIImage*)image error:(NSError*)error {	// this should be called on main thread
	self.loading = NO;
	
	self.loadingTook = [NSDate.date timeIntervalSinceDate:_startedLoadingAt];
	self.startedLoadingAt = nil;
	
	if (error || !image) {
		if (_completetionTarget && _failureSelector)
			[_completetionTarget performSelector:_failureSelector withObject:error withObject:self];
		else if (_onLoad)
			_onLoad(nil);
		
		return;
	}
	if (_completetionTarget && _completetionSelector)
		[_completetionTarget performSelector:_completetionSelector withObject:image withObject:self];
	else if (_onLoad)
		_onLoad(image);
	
	if (_crossfadeImages && image && image != _placeholderImage && _loadingTook > .03) {
		CATransition* animation = [CATransition animation];
		animation.type = kCATransitionFade;
		animation.duration = .35;
		[self.layer addAnimation:animation forKey:nil];
	}

	[self setImageFromAnyThread:image];
}
- (void)setImage:(UIImage *)image {
	[super setImage:image];
	if (_placeholderImage && image == _placeholderImage)
		super.contentMode = self.placeholderContentMode;
	else if (image)
		super.contentMode = self.loadedImageContentMode;
}

#pragma mark - Inter Threading

- (void)setImageFromAnyThread:(UIImage*)image {
	if ([NSThread.currentThread isMainThread]) {
		self.image = image;
	} else {
		FMNetworkImageOperation* operation = FMNetworkImageOperation.currentOperation;
		
		dispatch_sync(dispatch_get_main_queue(), ^{
			if (operation.isCancelled) return;
			[self setImage:image];
		});
	}
}
- (void)doneLoadingImageFromAnyThread:(UIImage*)image {
	if ([NSThread.currentThread isMainThread]) {
		[self doneLoadingImage:image error:nil];
	} else {
		if ([FMNetworkImageOperation.currentOperation isCancelled]) return;
		
		FMNetworkImageOperation* operation = FMNetworkImageOperation.currentOperation;
		
		dispatch_sync(dispatch_get_main_queue(), ^{
			if (operation.isCancelled) return;
			[self doneLoadingImage:image];
		});
	}
}

#pragma mark - Networking

+ (UIImage *)cachedImageForURL:(NSURL *)imageURL {

	NSURLRequest* aRequest = [NSURLRequest requestWithURL:imageURL];
	NSCachedURLResponse* cachedResponse = [NSURLCache.sharedURLCache cachedResponseForRequest:aRequest];
	if (cachedResponse) {
		UIImage* image = [UIImage imageWithData:[cachedResponse data]];
		return image;
	}

	return nil;
}
- (void)loadedFromNetwork:(UIImage*)image {
	self.imageToDecompress = image;
	[self schedule:@selector(decodeImage)];
}
- (void)initiateLoad:(NSURL*)url {
	if (_loading)
		[self cancelLoading];
	[self stopQueue];
	
	self.startedLoadingAt = NSDate.date;

	[self schedule:@selector(realInitiateWithURL:) withObject:url];
}
- (void)realInitiateWithURL:(NSURL*)url {
	
	if ([FMNetworkImageOperation.currentOperation isCancelled]) return;
	
	// check for cached image
	UIImage* cached = [self.class cachedImageForURL:url];
	if (cached) {
		FMNetworkImageOperation* operation = FMNetworkImageOperation.currentOperation;
		
		dispatch_sync(dispatch_get_main_queue(), ^{
			if (operation.isCancelled) return;
			[self doneLoadingImage:cached];
		});
		return;
	}
	
	// show placeholder
	if (!self.image && _placeholderImage) {
		[self setImageFromAnyThread:_placeholderImage];
	}
	
	// Delay Before Loading (image might be scrolling through screen really fast)
	if (_delayBeforeLoading > 0) {
		mach_timebase_info_data_t timeBaseInfo;
		mach_timebase_info(&timeBaseInfo);
		
		uint64_t time_a = mach_absolute_time();
		double elapsedTime = 0;
		while (elapsedTime / 1000.0 < _delayBeforeLoading && ![FMNetworkImageOperation.currentOperation isCancelled]) {
			[NSThread sleepForTimeInterval:.005]; // 5ms
			
			uint64_t time_b = mach_absolute_time();
			elapsedTime = ((time_b - time_a) * timeBaseInfo.numer / timeBaseInfo.denom) / 1000000.0;
		}
	}
	
	// Might be cancelled, DO NOT REFER TO SELF OR ANY OBJECT UNTIL THIS POINT, in case dealloc is called, it might crash
	if ([FMNetworkImageOperation.currentOperation isCancelled]) {
		return;
	}
	
	// Start. No return.
	self.loading = YES;
	self.startedLoadingAt = NSDate.date;

	self.data = NSMutableData.data;
	NSURLRequest* aRequest = [NSURLRequest requestWithURL:url];
	self.conn = [NSURLConnection.alloc initWithRequest:aRequest delegate:self startImmediately:NO].autorelease;
	[self.conn setDelegateQueue:self.class.operationQueue];
	[self.conn start];
}
- (void)cancelLoading {

	if (self.conn) {
		[self.conn cancel];
		self.conn = nil;
		self.data = nil;
	}

	[_imageURL autorelease]; _imageURL = nil;

	[self stopQueue];
	
	self.loading = NO;
	if (_placeholderImage) {
		[self setImageFromAnyThread:_placeholderImage];
	}
}
- (UIViewContentMode)placeholderContentMode {
	if (_placeholderContentMode == 0)
		return self.contentMode;
	return _placeholderContentMode;
}
- (UIViewContentMode)loadedImageContentMode {
	if (_loadedImageContentMode == 0)
		return self.contentMode;
	return _loadedImageContentMode;
}

- (void)decodeImage {
	
	if ([FMNetworkImageOperation.currentOperation isCancelled])
		return;
	
	if ([NSThread.currentThread isMainThread]) {
		[[NSException exceptionWithName:@"MainThreadException" reason:@"Dont call -decodeImage from main thread" userInfo:nil] raise];
		return;
	}
	UIImage* imageToDecompress = self.imageToDecompress.retain;
	if (!imageToDecompress) return;
	
	if (!_imageScale || _imageScale < 1)
		_imageScale = 1.0;
		
	CGImageRef imageRef = imageToDecompress.CGImage;
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(NULL,
												 CGImageGetWidth(imageRef),
												 CGImageGetHeight(imageRef),
												 8,
												 // Just always return width * 4 will be enough
												 CGImageGetWidth(imageRef) * 4,
												 // System only supports RGB, set explicitly
												 colorSpace,
												 // Makes system don't need to do extra conversion when displayed.
												 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
	CGColorSpaceRelease(colorSpace);
	if (!context) {
		[imageToDecompress release];
		return;
	}
	if ([FMNetworkImageOperation.currentOperation isCancelled]) {
		CGContextRelease(context);
		[imageToDecompress release];
		return;
	}
	
	CGRect rect = (CGRect){CGPointZero,{CGImageGetWidth(imageRef), CGImageGetHeight(imageRef)}};
	CGContextDrawImage(context, rect, imageRef);
	CGImageRef decompressedImageRef = CGBitmapContextCreateImage(context);
	CGContextRelease(context);
	
	UIImage *decompressedImage = [[UIImage alloc] initWithCGImage:decompressedImageRef scale:_imageScale orientation:UIImageOrientationUp];
	CGImageRelease(decompressedImageRef);
	
	if ([FMNetworkImageOperation.currentOperation isCancelled] || self.imageToDecompress != imageToDecompress) {
		[decompressedImage release];
		[imageToDecompress release];
		return;
	}
	[imageToDecompress release];
	
	[self decodedImageInto:decompressedImage];
	[decompressedImage release];
}
- (void)decodedImageInto:(UIImage*)decodedImage {
	self.imageToDecompress = nil;
	FMNetworkImageOperation* operation = FMNetworkImageOperation.currentOperation;
	
	dispatch_sync(dispatch_get_main_queue(), ^{
		if (operation.isCancelled) return;
		[self doneLoadingImage:decodedImage];
	});
}

@end

@implementation FMNetworkImage (NSURLConnection)

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	FMNetworkImageOperation* operation = FMNetworkImageOperation.currentOperation;
	
	dispatch_sync(dispatch_get_main_queue(), ^{
		if (operation.isCancelled) return;
		[self doneLoadingImage:nil];
	});
	self.conn = nil;
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	[self.data appendData:data];
	if ([FMNetworkImageOperation.currentOperation isCancelled]) {
		[connection cancel];
		self.data = nil;
		self.conn = nil;
		return;
	}
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	// ..
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	if ([FMNetworkImageOperation.currentOperation isCancelled]) return;
	
	[self schedule:@selector(processData)];
	self.conn = nil;
}
- (void)processData { // runs in another thread
//	[self log:@"processing data"];
	
	NSData* data = self.data;
	[data retain];
	self.data = nil;
	UIImage* image = [UIImage imageWithData:data];
	[data release];
	
	if ([FMNetworkImageOperation.currentOperation isCancelled]) return;
	self.imageToDecompress = image;
	[self decodeImage];
}

@end

@implementation FMNetworkImageOperation : NSOperation

- (void)dealloc {
	self.parameter = nil;
	[super dealloc];
}
+ (FMNetworkImageOperation*)operationWithOwner:(id)owner selector:(SEL)selector {
	return [self.class operationWithOwner:owner target:owner selector:selector];
}
+ (FMNetworkImageOperation*)operationWithOwner:(id)owner target:(id)target selector:(SEL)selector {
	FMNetworkImageOperation* operation = FMNetworkImageOperation.new.autorelease;
	operation.owner = owner;
	operation.target = target;
	operation.selector = selector;
	operation.threadPriority = .95;
	return operation;
}
+ (FMNetworkImageOperation*)currentOperation {
	NSMutableArray* stack = [NSThread.currentThread.threadDictionary objectForKey:@"ops"];
	if (!stack) return nil;
	return [stack lastObject];
}
- (void)pushToStack {
	NSMutableArray* stack = [NSThread.currentThread.threadDictionary objectForKey:@"ops"];
	if (!stack) {
		stack = NSMutableArray.array;
		[NSThread.currentThread.threadDictionary setObject:stack forKey:@"ops"];
	}
	[stack addObject:self];
}
- (void)popFromStack {
	NSMutableArray* stack = [NSThread.currentThread.threadDictionary objectForKey:@"ops"];
	if (!stack) return;
	id obj = [stack lastObject];
	if (!obj || obj != self) return;
	[stack removeObject:self];
}
- (void)main {
	[self pushToStack];
	[_target performSelector:_selector withObject:_parameter];
	self.parameter = nil;
	[self popFromStack];
}

@end
