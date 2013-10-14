FMNetworkImage
==============

An Async-Network-Image-Loader for iOS

After working with a few other alternatives, I ended up writing my own one. 
Codes might be a little bit of ugly, but I aimed for performance in this. Especially in 
table views, scrolling fast through images.

Features / News
===============

*14th October 2013:*

- Decoded Image Cache support added, Using [NSCache](https://developer.apple.com/library/ios/documentation/cocoa/reference/NSCache_Class/Reference/Reference.html)

** More About Decoded Image Cache **

```objc
// Note : You only need this in cases, where loaded images are bigger/smaller than the imageView, needs cropping/resizing.

// This will make FMNetworkImage crop & resize your image in background to fit your imageView
myImageview.netImage.fixImageCropResize = YES;

// This will make cropped/resized/decoded image to be cached (not to be confused with url cache, this is RAW Bitmap)
myImageview.netImage.cacheDecodedResults = YES;
```

The cache used here, will consume much more memory, but will be freed automatically when needed. All handled by [NSCache](https://developer.apple.com/library/ios/documentation/cocoa/reference/NSCache_Class/Reference/Reference.html) implementation of apple. Since the RAW Bitmap of resized image is cached, the UI Thread (Main Thread) will not deal with these and everything will work smoothly on UI.

When an image gets deleted from this cache, and you try to load that image again, it will be loaded from URL Cache, and will get decoded/resized/cropped/whatever again, which is still OK.

You should not use `fixImageCropResize` if you are going to resize that imageView randomly.

===

*13th October 2013:*

- Code converted to use a ImageView Category, `UIImageView+FMNetworkImage`, with Obj-C Associated Objects. *( Old code for separate view class is remaining, but is outdated now. )*
- Background resizing (respecting contentMode) for images with different size than imageView, eliminating glitches in UI when setting the image in the main thread.

===

*Originally:*

- Background Fetching
- Optional Delay before fetch 
  *( So you use this to prevent loading an image for a cell that's gonna be displayed for 1.5 miliseconds ( not 1.5ms literally :/ ) )*
- Optional Cross-Fade after load
- Placeholder Image
- `(UIImage*)onLoad(UIImage* loadedImage)` hook using blocks
- Automatically changing between UIViewContent modes when showing loading image or placeholder image
- Making use of NSOperationQueue
- Background Decoding (ripoff from [SDWebImage](https://github.com/rs/SDWebImage), thanks for that)

Usage
=====

**Simply**
```objc
// on any UIImageView
myImageView.netImage.URL = [NSURL URLWithString:@"http://url.to/my/image"];
```

**Compatibility Shortcut**
```objc
myImageView.imageURL = [NSURL URLWithString:@"http://url.to/my/image"];
```

**Advanced Usage**
```objc
UIImageView* imageView = [UIImageView.alloc initWithFrame:CGRectInset(self.frame, 10, 10)].autorelease;
imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth + UIViewAutoresizingFlexibleHeight;
imageView.backgroundColor = UIColor.darkGrayColor;
imageView.netImage.placeholderImage = [UIImage imageNamed:@"placeholder.png"];
imageView.netImage.placeholderContentMode = UIViewContentModeCenter;
imageView.netImage.loadedImageContentMode = UIViewContentModeScaleAspectFill;
imageView.netImage.crossfadeImages = YES;
imageView.netImage.delayBeforeLoading = 1.0 / 30.0;
imageView.netImage.fixImageCropResize = YES;
imageView.netImage.cacheDecodedResults = YES;
imageView.clipsToBounds = YES;

imageView.netImage.URL = @"http://url.to/my/image";
```

**UITableViewCell / UICollectionViewCell Notes**
```objc
- (void)prepareForReuse {
	imageView.netImage.URL = nil; // Sets image to placeholderImage or empty if no placeholder image is present.
}
```	

Install
=======

Just Copy `UIImageView+FMNetworkImage.(m|h)` in your project. I don't like `bundle`,`composer`,`pip`,`pod`,`npm` at all.
I like `apt` though.

Notes
=====

 **DOESN'T** use ARC. If you're using ARC in your project, you'll need `-fno-objc-arc` for `UIImageView+FMNetworkImage.m` [need help?](http://stackoverflow.com/questions/6646052/how-can-i-disable-arc-for-a-single-file-in-a-project)

License
=======

 **INFORMATION DOES NOT BELONG TO ANY BODY** 
 
 Just to prevent somebody claiming otherwise over this code, license for any other purpose
 than iOS Projects is [GPLv3](http://www.gnu.org/copyleft/gpl.html), but since you want 
 to use this in your iOS project, *-only applies to iOS Projects-* [MIT License](http://opensource.org/licenses/MIT)
 rules apply. ( does it even work that way? ).

 I used and learned stuff from other libraries, [AsyncImageView](https://github.com/nicklockwood/AsyncImageView), 
 [SDWebImage](https://github.com/rs/SDWebImage) as mentioned above, maybe a few more on this, I don't remember at all.
