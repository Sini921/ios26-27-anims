TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = iOS2627Anims
iOS2627Anims_FILES = Tweak.x
# Older libobjc runtimes cannot load signed class_ro pointers from new clang.
iOS2627Anims_CFLAGS = -fobjc-arc -Wall -Wextra -fno-ptrauth-objc-class-ro
iOS2627Anims_FRAMEWORKS = UIKit QuartzCore CoreGraphics
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
