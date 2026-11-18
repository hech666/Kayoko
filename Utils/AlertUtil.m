//
//  AlertUtil.m
//  Kayoko
//
//  Created by Alexandra Aurora Göttischer
//

#import "AlertUtil.h"

@implementation AlertUtil
/**
 * Shows a core foundation alert.
 *
 * @param title The title of the alert.
 * @param message The message displayed on the alert.
 * @param dismissButtonTitle The title of the dismiss button.
 */
+ (void)showAlertWithTitle:(NSString *)title andMessage:(NSString *)message withDismissButtonTitle:(NSString *)dismissButtonTitle {
    // CFUserNotification API is unavailable on iOS.
    // This method is currently unused in the codebase.
}
@end
