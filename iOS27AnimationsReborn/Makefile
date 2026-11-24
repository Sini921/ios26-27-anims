TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = iOS27AnimsReborn
iOS27AnimsReborn_FILES = Tweak.x
# Older libobjc runtimes cannot load signed class_ro pointers from new clang.
iOS27AnimsReborn_CFLAGS = -fobjc-arc -Wall -Wextra -fno-ptrauth-objc-class-ro
iOS27AnimsReborn_FRAMEWORKS = UIKit QuartzCore CoreGraphics
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
