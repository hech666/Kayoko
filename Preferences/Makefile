BUNDLE_NAME = KayokoPreferences
# Settings only needs its controllers/cells; clipboard services run in the tweaks.
KayokoPreferences_FILES = $(wildcard Controllers/*.m Cells/*.m)
KayokoPreferences_FRAMEWORKS = UIKit
KayokoPreferences_PRIVATE_FRAMEWORKS = Preferences
KayokoPreferences_INSTALL_PATH = /Library/PreferenceBundles
KayokoPreferences_CFLAGS = -fobjc-arc -DTHEOS_LEAN_AND_MEAN

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk
