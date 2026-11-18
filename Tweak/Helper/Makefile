TWEAK_NAME = KayokoHelper
KayokoHelper_FILES = KayokoHelper.m $(wildcard ../../Manager/*.m ../../Utils/*.m)
KayokoHelper_CFLAGS = -fobjc-arc -DTHEOS_LEAN_AND_MEAN
KayokoHelper_FRAMEWORKS = UIKit
KayokoHelper_LDFLAGS = -L$(THEOS)/vendor/lib -lsandy

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
include $(THEOS_MAKE_PATH)/tweak.mk
