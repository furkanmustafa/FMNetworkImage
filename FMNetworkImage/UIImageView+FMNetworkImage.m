//
//  UIImageView+FMNetworkImage.m
//
//  Created by Furkan Mustafa on 10/12/13.
//

#import "UIImageView+FMNetworkImage.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>

// Uncomment to see how much decoding takes in logs
//#define FMNetworkImage_Profiling

@implementation UIImageView (FMNetworkImageCategory)
- (void)setNetImage:(FMNetworkImage *)netImage {
	objc_setAssociatedObject(self, @selector(netImage), netImage, OBJC_ASSOCIATION_RETAIN);
}
- (FMNetworkImage *)netImage {
	FMNetworkImage *pack = objc_getAssociatedObject(self, @selector(netImage));
	if (!pack) {
		[FMNetworkImage attachTo:self];
		pack = objc_getAssociatedObject(self, @selector(netImage));
	}
	return pack;
}

- (void)setImageURL:(NSURL *)imageURL {
	self.netImage.URL = imageURL;
}
- (NSURL *)imageURL {
	return self.netImage.URL;
}

@end

#pragma mark - Pack

@interface FMNetworkImageConnectionDelegate : NSObject <NSURLConnectionDelegate,NSURLConnectionDataDelegate> {
	FMNetworkImage* _netImage;
}
- (void)cancel;
- (id)initWithFMNetworkImage:(FMNetworkImage*)netImage;
@property (atomic,retain) NSURLConnection* conn;
@property (atomic,retain) NSMutableData* data;
@property (nonatomic,assign) FMNetworkImage* netImage;
@end

@interface FMNetworkImage ()
@property (nonatomic,readwrite) FMNetworkImageStatus status;
@property (atomic,assign) FMNetworkImageConnectionDelegate* connectionDelegate;
- (void)processData:(NSData*)data;
@end

@interface FMNetworkImageOperation : NSOperation
@property (nonatomic,assign) id owner;
@property (nonatomic,assign) id target;
@property (nonatomic,assign) SEL selector;
@property (nonatomic,copy) id parameter;
+ (FMNetworkImageOperation*)operationWithOwner:(id)owner selector:(SEL)selector;
+ (FMNetworkImageOperation*)operationWithOwner:(id)owner target:(id)target selector:(SEL)selector;
+ (FMNetworkImageOperation*)currentOperation;
+ (NSOperationQueue*)queue;
@end

@implementation FMNetworkImage

- (void)dealloc {
	if (self.connectionDelegate) {
		self.connectionDelegate.netImage = nil;
		[self.connectionDelegate cancel];
		self.connectionDelegate = nil;
	}
	self.imageReceiver = nil;
	[self cancelLoading];

	self.onLoad = nil;
	self.rawRemoteImage = nil;
	self.placeholderImage = nil;
	self.startedLoadingAt = nil;
	self.queue = nil;
	[super dealloc];
}

- (void)log:(NSString*)format, ... NS_FORMAT_FUNCTION(1, 2) {
#ifdef DEBUG
	va_list args;
	va_start(args, format);
	NSString* logMessage = [NSString.alloc initWithFormat:format arguments:args].autorelease;
	NSLog(@"[%@:%2lx] imageView:%2lx %@", NSStringFromClass(self.class), (unsigned long)self, (unsigned long)_imageReceiver, logMessage);
	va_end(args);
#endif
}

+ (void)attachTo:(id<FMNetworkImageAttachable>)object {
	object.netImage = [FMNetworkImage.new autorelease];
	object.netImage.imageReceiver = object;
}

// Operation queue for downloading, processing and decoding images
- (void)schedule:(SEL)selector {
	[self.queue addOperation:[FMNetworkImageOperation operationWithOwner:self selector:selector]];
}
- (void)schedule:(SEL)selector withObject:(id)object {
	FMNetworkImageOperation* op = [FMNetworkImageOperation operationWithOwner:self selector:selector];
	op.parameter = object;
	[self.queue addOperation:op];
}
- (void)schedule:(SEL)selector on:(id)target {
	[self.queue addOperation:[FMNetworkImageOperation operationWithOwner:self target:target selector:selector]];
}
- (void)stopQueue {
	for (FMNetworkImageOperation* operation in [self.queue.operations.copy autorelease]) {
		if ([operation isKindOfClass:FMNetworkImageOperation.class] && operation.owner==self)
			[operation cancel];
	}
}

- (void)setURL:(NSURL *)URL target:(id)target success:(SEL)success failure:(SEL)failure {
	self.completetionTarget = target;
	self.completetionSelector = success;
	self.failureSelector = failure;
	self.URL = URL;
}
- (void)setURL:(NSURL *)URL completionBlock:(void (^)(UIImage * image))onLoad {
	self.onLoad = onLoad;
	self.URL = URL;
}
- (void)setURL:(NSURL *)URL {
	if (URL==_URL || (_URL && URL && [URL.absoluteString isEqualToString:_URL.absoluteString])) return;
	[self cancelLoading];
	
	[_URL autorelease]; _URL = [URL retain];
	if (URL) {
		[self initiateLoad:URL];
	} else if (_placeholderImage) {
		self.image = _placeholderImage;
	} else {
		self.image = nil;
	}
}

- (CGSize)imageViewPixelSize {
	if ([self.imageReceiver isKindOfClass:UIImageView.class])
		return (CGSize){ [(UIImageView*)self.imageReceiver bounds].size.width * _imageScale, [(UIImageView*)self.imageReceiver bounds].size.height * _imageScale };
	return CGSizeZero;
}

- (UIViewContentMode)placeholderContentMode {
	if (_placeholderContentMode)
		return _placeholderContentMode;
	if ([self.imageReceiver isKindOfClass:UIImageView.class])
		return [(UIImageView*)self.imageReceiver contentMode];
	return _placeholderContentMode;
}
- (UIViewContentMode)loadedImageContentMode {
	if (_loadedImageContentMode)
		return _loadedImageContentMode;
	if ([self.imageReceiver isKindOfClass:UIImageView.class])
		return [(UIImageView*)self.imageReceiver contentMode];
	return _placeholderContentMode;
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
	
	if (_crossfadeImages && image && [self.imageReceiver isKindOfClass:UIImageView.class] && image != _placeholderImage && _loadingTook > .03) { // && !_loadingFromCacheDontFade
#ifdef QUARTZCORE_H
		CATransition* animation = [CATransition animation];
		animation.type = kCATransitionFade;
		animation.duration = .35;
		[[(UIImageView*)self.imageReceiver layer] addAnimation:animation forKey:nil];
#else
		[NSException exceptionWithName:@"com.fume.FMNetworkImage.QuartzCoreDisabled"
								reason:@"If you want crossfading, you'll need to add QuarzCore Framework" userInfo:nil];
#endif
	}
	
	[self setImageFromAnyThread:image];
}
- (void)setImage:(UIImage *)image {
	self.imageReceiver.image = image;
	if (![self.imageReceiver isKindOfClass:UIImageView.class]) return;
	
	if (_placeholderImage && image == _placeholderImage)
		[(UIImageView*)self.imageReceiver setContentMode:self.placeholderContentMode];
	else if (image) {
		[(UIImageView*)self.imageReceiver setContentMode:self.loadedImageContentMode];
	}
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
	self.rawRemoteImage = image;
	[self schedule:@selector(decodeImage)];
}
- (void)initiateLoad:(NSURL*)url {
	if (_loading)
		[self cancelLoading];
	[self stopQueue];
	
	self.startedLoadingAt = NSDate.date;
	self.status = FMNetworkImageStatus_PriorDelay;
	[self schedule:@selector(realInitiateWithURL:) withObject:url];
}
- (void)realInitiateWithURL:(NSURL*)url {
	
	if ([FMNetworkImageOperation.currentOperation isCancelled]) return;
	
	_loadingFromCacheDontFade = NO;
	
	// Decoded Image Cache
	if (_fixImageCropResize) {
		UIImage* decodedCache = [self.class cachedDecodedImageForSourceURL:url
																 resizedTo:self.imageViewPixelSize
														  usingContentMode:self.loadedImageContentMode];
		if (decodedCache) {
			_loadingFromCacheDontFade = YES;
//			[self log:@"Resized Cache"];
			[self doneLoadingImageFromAnyThread:decodedCache];
			return;
		}
	}
	
	// URL Cache
	// TODO : Make this async, while waiting for delay (if there is a delayBeforeLoading set)
	UIImage* cached = [self.class cachedImageForURL:url];
	if (cached) {
		_loadingFromCacheDontFade = YES;
//		[self log:@"URL Cache"];

		self.rawRemoteImage = cached;
		[self schedule:@selector(decodeImage)];
		
		return;
	}
	
	// show placeholder
	if (!self.imageReceiver.image && _placeholderImage) {
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
	
	self.status = FMNetworkImageStatus_RemoteFetch;
	
	// Start. No return.
	self.loading = YES;
	self.startedLoadingAt = NSDate.date;
	
	NSURLRequest* aRequest = [NSURLRequest requestWithURL:url];
	FMNetworkImageConnectionDelegate* delegate = [[FMNetworkImageConnectionDelegate.alloc initWithFMNetworkImage:self] autorelease];
	delegate.conn = [NSURLConnection.alloc initWithRequest:aRequest delegate:delegate startImmediately:NO].autorelease;

	[delegate.conn setDelegateQueue:self.queue];
	[delegate.conn start];
}
- (void)cancelLoading {
	
	self.status = FMNetworkImageStatus_Idle;
	
	if (self.connectionDelegate) {
		[self.connectionDelegate cancel];
	}
	
	[_URL autorelease]; _URL = nil;
	
	[self stopQueue];
	
	self.loading = NO;
	if (_placeholderImage) {
		[self setImageFromAnyThread:_placeholderImage];
	}
}

- (void)decodeImage {
	
	if ([FMNetworkImageOperation.currentOperation isCancelled])
		return;
	
	if ([NSThread.currentThread isMainThread]) {
		[[NSException exceptionWithName:@"MainThreadException" reason:@"Dont call -decodeImage from main thread" userInfo:nil] raise];
		return;
	}

	UIImage* imageToDecompress = self.rawRemoteImage.retain;
	if (!imageToDecompress) return;
	self.rawRemoteImage = nil; // release

	NSURL* processingURL = [self.URL.retain autorelease];

#if defined(FMNetworkImage_Profiling) && defined(DEBUG)
	mach_timebase_info_data_t timeBaseInfo;
	mach_timebase_info(&timeBaseInfo);
	
	uint64_t time_a = mach_absolute_time();
	double elapsedTime = 0;
#endif
	
	self.status = FMNetworkImageStatus_Decode;
	
	CGSize receiverSize = self.imageViewPixelSize;
	UIViewContentMode contentMode = self.loadedImageContentMode;
	
	if (!_imageScale || _imageScale < 1)
		_imageScale = UIScreen.mainScreen.scale;
	
	CGSize imageSize = CGSizeMake(imageToDecompress.size.width * imageToDecompress.scale, imageToDecompress.size.height * imageToDecompress.scale);
	CGSize targetSize = imageSize;
	CGRect targetRect = (CGRect){ CGPointZero, targetSize };
	
	if (_fixImageCropResize) { // determine cropping / resize
		CGFloat imageAspectRatio = imageToDecompress.size.width / imageToDecompress.size.height;
		CGFloat viewAspectRatio = receiverSize.width / receiverSize.height;
		CGPoint viewImageRatio = (CGPoint){
			receiverSize.width / imageToDecompress.size.width,
			receiverSize.height / imageToDecompress.size.height
		};
		
		if (contentMode == UIViewContentModeScaleAspectFill) { // most widely used
			
			if (viewAspectRatio > imageAspectRatio) {
				targetRect.size.height = (int)floorf(imageToDecompress.size.width * receiverSize.height / receiverSize.width);
				targetRect.origin.y += (int)floorf((imageToDecompress.size.height - targetRect.size.height) / 2.0);
			} else {
				targetRect.size.width = (int)floorf(imageToDecompress.size.height  * receiverSize.width / receiverSize.height);
				targetRect.origin.x += (int)floorf((imageToDecompress.size.width - targetRect.size.width) / 2.0);
			}
			
			targetSize = receiverSize;
		} else
			if (contentMode == UIViewContentModeScaleAspectFit) { // most widely used
				CGFloat multiplyRatio = MIN(viewImageRatio.x, viewImageRatio.y);
				
				targetSize = (CGSize){ (int)floorf(imageToDecompress.size.width * multiplyRatio), (int)floorf(imageToDecompress.size.height * multiplyRatio) };
			} else
				if (contentMode == UIViewContentModeScaleToFill) {
					targetSize = receiverSize;
				} else {
					targetSize = receiverSize;
					targetRect.size = targetSize;
					
					if (contentMode == UIViewContentModeCenter || contentMode == UIViewContentModeTop || contentMode == UIViewContentModeBottom) {
						targetRect.origin.x = (int)floorf((imageSize.width - targetRect.size.width) / 2);
					}
					if (contentMode == UIViewContentModeBottomRight || contentMode == UIViewContentModeRight || contentMode == UIViewContentModeTopRight) {
						targetRect.origin.x = imageSize.width - targetRect.size.width;
					}
					if (contentMode == UIViewContentModeCenter || contentMode == UIViewContentModeLeft || contentMode == UIViewContentModeRight) {
						targetRect.origin.y = (int)floorf((imageSize.height - targetRect.size.height) / 2);
					}
					if (contentMode == UIViewContentModeBottom || contentMode == UIViewContentModeBottomLeft || contentMode == UIViewContentModeBottomRight) {
						targetRect.origin.y = imageSize.height - targetRect.size.height;
					}
				}
		
	}
	
	CGImageRef imageRef = CGImageRetain(imageToDecompress.CGImage);
	
	if (_fixImageCropResize) {
		
		CGImageRef filtered = CGImageRetain(imageRef);
		
		// CROP Process
		if (targetRect.origin.x != 0 || targetRect.origin.y != 0 || !CGSizeEqualToSize(targetRect.size, imageSize)) {
			
			CGImageRef new = CGImageCreateWithImageInRect(imageToDecompress.CGImage, targetRect);
			CGImageRelease(filtered);
			filtered = new;
			
		}
		
		// RESIZE Image
		if (!CGSizeEqualToSize((CGSize){ CGImageGetWidth(filtered), CGImageGetHeight(filtered) }, targetSize)) {
			
			// do plug-in resizing here.. like using GPUImage or sth.
		
		}
		
		if (filtered != imageRef) {
			CGImageRelease(imageRef);
			imageRef = filtered;
		}
	}
	[imageToDecompress release];
	
#if defined(FMNetworkImage_Profiling) && defined(DEBUG)
	{	uint64_t time_ba = mach_absolute_time();
		elapsedTime = ((time_ba - time_a) * timeBaseInfo.numer / timeBaseInfo.denom) / 1000000.0;
		[self log:@"Decoding .... : %.3f ms, ..", elapsedTime]; }
#endif
	
	// COLORSPACE FIX ( Convert to final state like UIImageView is going to use, Got this part from SDWebImage )
	CGColorSpaceRef deviceColorSpace = CGColorSpaceCreateDeviceRGB();
	CGColorSpaceRef currentColorSpace = CGImageGetColorSpace(imageRef);
	CGBitmapInfo currentBitmapInfo = CGImageGetBitmapInfo(imageRef);
	CGSize currentSize = (CGSize){ CGImageGetWidth(imageRef), CGImageGetHeight(imageRef) };
	
	if (!CGSizeEqualToSize(currentSize, targetSize) ||
		CGColorSpaceGetModel(currentColorSpace)!=CGColorSpaceGetModel(deviceColorSpace) ||
		!(currentBitmapInfo & (kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little))) {
		
		CGContextRef context = CGBitmapContextCreate(NULL,
													 targetSize.width,
													 targetSize.height,
													 8,
													 // Just always return width * 4 will be enough
													 targetSize.width * 4,
													 // System only supports RGB, set explicitly
													 deviceColorSpace,
													 // Makes system don't need to do extra conversion when displayed.
													 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
		if (!context) {
			// FAILS :/
			CGColorSpaceRelease(deviceColorSpace);
			CGImageRelease(imageRef);
			return;
		}
		
		CGRect rect = (CGRect){ CGPointZero, targetSize };
		CGContextDrawImage(context, rect, imageRef);
		CGImageRef decompressedImageRef = CGBitmapContextCreateImage(context);
		CGContextRelease(context);
		
		CGImageRelease(imageRef);
		imageRef = decompressedImageRef;
	}
	CGColorSpaceRelease(deviceColorSpace);
	
	if ([FMNetworkImageOperation.currentOperation isCancelled]) {
		CGImageRelease(imageRef);
		return;
	}
	
#if defined(FMNetworkImage_Profiling) && defined(DEBUG)
	{	uint64_t time_ba = mach_absolute_time();
		elapsedTime = ((time_ba - time_a) * timeBaseInfo.numer / timeBaseInfo.denom) / 1000000.0;
		[self log:@"Decoding .... : %.3f ms, ..", elapsedTime]; }
#endif
	
	// Finally the UIImage (retained)
	UIImage *decompressedImage = [[UIImage alloc] initWithCGImage:imageRef scale:_imageScale orientation:UIImageOrientationUp];
	CGImageRelease(imageRef);
	
	if (_cacheDecodedResults) {
		[self.class saveDecodedImage:decompressedImage forSourceURL:processingURL resizedTo:targetSize usingContentMode:contentMode];
	}
	
#if defined(FMNetworkImage_Profiling) && defined(DEBUG)
	uint64_t time_b = mach_absolute_time();
	elapsedTime = ((time_b - time_a) * timeBaseInfo.numer / timeBaseInfo.denom) / 1000000.0;
	[self log:@"Decoding took : %.3f ms, Size : %@", elapsedTime, NSStringFromCGSize(decompressedImage.size)];
#endif
	
	if ([FMNetworkImageOperation.currentOperation isCancelled]) {
		[decompressedImage release];
		return;
	}
	
	[self decodedImageInto:decompressedImage];
	[decompressedImage release];
}
- (void)decodedImageInto:(UIImage*)decodedImage {
	FMNetworkImageOperation* operation = FMNetworkImageOperation.currentOperation;
	
	dispatch_sync(dispatch_get_main_queue(), ^{
		if (operation.isCancelled) return;
		if (decodedImage)
			self.status = FMNetworkImageStatus_Loaded;
		[self doneLoadingImage:decodedImage];
	});
}

- (void)processData:(NSData*)data {
//	[self log:@"processing data"];
	
	self.status = FMNetworkImageStatus_Convert;
	
	UIImage* image = [UIImage imageWithData:data];
	
	if ([FMNetworkImageOperation.currentOperation isCancelled]) return;
	
	self.rawRemoteImage = image;
	[self decodeImage];
}

- (NSOperationQueue *)queue {
	return FMNetworkImageOperation.queue;
	
//	if (!_queue) {
//		@synchronized (self) {
//			if (!_queue)
//				_queue = [NSOperationQueue new];
//		}
//	}
//	return _queue;
}

@end

@implementation FMNetworkImageConnectionDelegate

- (void)dealloc {
	self.netImage = nil;
	[self cancel];
	[super dealloc];
}
- (id)initWithFMNetworkImage:(FMNetworkImage*)netImage {
    self = [super init];
    if (self) {
		self.netImage = netImage;
        self.data = NSMutableData.data;
    }
    return self;
}
- (void)cancel {
	@synchronized (self) {
		self.data = nil;
		if (self.conn) {
			[self.conn cancel];
			self.conn = nil;
		}
	}
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	[self retain];
	self.conn = nil;
	[self.netImage doneLoadingImageFromAnyThread:nil];
	[self release];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	if ([FMNetworkImageOperation.currentOperation isCancelled]) {
		[self cancel];
		return;
	}
	[self.data appendData:data];
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	// ..
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	[self retain];
	self.conn = nil;
	if ([FMNetworkImageOperation.currentOperation isCancelled]) {
		[self release];
		return;
	}
	
	[self.netImage schedule:@selector(processData:) withObject:self.data];
	[self release];
}

- (void)setNetImage:(FMNetworkImage *)netImage {
	@synchronized (self) {
		_netImage.connectionDelegate = nil;
		
		_netImage = netImage;
		
		_netImage.connectionDelegate = self;
	}
}
- (FMNetworkImage *)netImage {
	__block FMNetworkImage* netImage = nil;
	@synchronized (self) {
		netImage = _netImage;
	}
	return netImage;
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
+ (NSOperationQueue*)queue { //sharedQueue
	static NSOperationQueue* queue;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		queue = [NSOperationQueue new];
		queue.name = @"FMNetworkImage Queue";
	});
	return queue;
}

@end

@implementation FMNetworkImage (DecodedImageCache)
+ (NSCache*)sharedCache {
	static NSCache* sharedCache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedCache = [NSCache new];
		sharedCache.name = @"FMNetworkImage Decoded Image Cache";
	});
	return sharedCache;
}
+ (UIImage*)cachedDecodedImageForKey:(NSString*)key {
	return [self.sharedCache objectForKey:key];
}
+ (NSString*)keyForCachedDecodedImageForSourceURL:(NSURL*)URL resizedTo:(CGSize)size usingContentMode:(UIViewContentMode)contentMode {
	return [NSString stringWithFormat:@"%d_%@_%d_%d", (int)contentMode, URL.absoluteString, (int)size.width, (int)size.height];
}
+ (void)saveDecodedImage:(UIImage*)image forSourceURL:(NSURL*)URL resizedTo:(CGSize)size usingContentMode:(UIViewContentMode)contentMode {
	[self.sharedCache setObject:image forKey:[self keyForCachedDecodedImageForSourceURL:URL resizedTo:size usingContentMode:contentMode]];
}
+ (UIImage*)cachedDecodedImageForSourceURL:(NSURL*)URL resizedTo:(CGSize)size usingContentMode:(UIViewContentMode)contentMode {
	return [self cachedDecodedImageForKey:[self keyForCachedDecodedImageForSourceURL:URL resizedTo:size usingContentMode:contentMode]];
}
@end

