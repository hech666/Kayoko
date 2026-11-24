//
//  NotificationKeys.h
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

static NSString* const kNotificationKeyObserverPasteboardChanged = @"codes.aurora.kayokod.pasteboard.changed";
static NSString* const kNotificationKeyCoreShow = @"codes.aurora.kayoko.core.show";
static NSString* const kNotificationKeyCoreHide = @"codes.aurora.kayoko.core.hide";
// Explicit outside-tap dismiss must not be swallowed by the keyboard/Squid guard.
static NSString* const kNotificationKeyCoreHideOutside = @"codes.aurora.kayoko.core.hide.outside";
// Compatibility with the original Kayoko bundle identifier.
static NSString* const kNotificationKeyLegacyCoreShow = @"dev.traurige.kayoko.core.show";
static NSString* const kNotificationKeyLegacyCoreHide = @"dev.traurige.kayoko.core.hide";
static NSString* const kNotificationKeyCoreReload = @"codes.aurora.kayoko.core.reload";
static NSString* const kNotificationKeyHelperPaste = @"codes.aurora.kayoko.helper.paste";
static NSString* const kNotificationKeyPreferencesReload = @"codes.aurora.kayoko.preferences.reload";
// Panel visibility state broadcast to Helper processes (for tap-outside-to-dismiss).
static NSString* const kNotificationKeyPanelDidShow = @"codes.aurora.kayoko.panel.didShow";
static NSString* const kNotificationKeyPanelDidHide = @"codes.aurora.kayoko.panel.didHide";
