// Test-only UIKit surface. Production builds always use the real iOS SDK.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface UIImage : NSObject
@property(nonatomic, readonly) CGImageRef CGImage;
+ (instancetype)imageWithContentsOfFile:(NSString *)path;
@end
FOUNDATION_EXPORT NSData *UIImagePNGRepresentation(UIImage *image);
FOUNDATION_EXPORT NSData *UIImageJPEGRepresentation(UIImage *image, CGFloat quality);
@interface UIPasteboard : NSObject
+ (instancetype)generalPasteboard;
@property(nonatomic) NSInteger changeCount;
@property(nonatomic) BOOL hasImages;
@property(nonatomic) BOOL hasStrings;
@property(nonatomic, copy) NSArray *strings;
@property(nonatomic, copy) NSArray *images;
@property(nonatomic, copy) NSString *string;
@property(nonatomic, strong) UIImage *image;
@end
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
@end
