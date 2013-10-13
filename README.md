FMNetworkImage
==============

An Async-Network-Image-Loader for iOS

After working with a few other alternatives, I ended up writing my own one. 
Codes might be a little bit of ugly, but I aimed for performance in this. Especially in 
table views, scrolling fast through images.

### Features

*As of 13th October 2013 :*

- Code converted to use a ImageView Category, `UIImageView+FMNetworkImage`, with Obj-C Associated Objects
- Background resizing (respecting contentMode) for images with different size than imageView, eliminating glitches in UI when setting the UI.
- Old code for separate view class is remaining, but is outdated now.

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

### Install

Just Copy `UIImageView+FMNetworkImage.(m|h)` in your project. I don't like `bundle`,`composer`,`pip`,`pod`,`npm` at all.
I like `apt` though.

### Notes

 **DOESN'T** use ARC. If you're using ARC in your project, you'll need `-fno-objc-arc` for `UIImageView+FMNetworkImage.m` [need help?](http://stackoverflow.com/questions/6646052/how-can-i-disable-arc-for-a-single-file-in-a-project)

### License

 **INFORMATION DOES NOT BELONG TO ANY BODY** 
 
 Just to prevent somebody claiming otherwise over this code, license for any other purpose
 than iOS Projects is [GPLv3](http://www.gnu.org/copyleft/gpl.html), but since you want 
 to use this in your iOS project, *-only applies to iOS Projects-* [MIT License](http://opensource.org/licenses/MIT)
 rules apply. ( does it even work that way? ).

 I used and learned stuff from other libraries, [AsyncImageView](https://github.com/nicklockwood/AsyncImageView), 
 [SDWebImage](https://github.com/rs/SDWebImage) as mentioned above, maybe a few more on this, I don't remember at all.
