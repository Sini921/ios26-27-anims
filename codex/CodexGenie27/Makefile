TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard
export TMPDIR := $(abspath ../tmp)
export CLANG_MODULE_CACHE_PATH := $(abspath ../cache)
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = iOS2627Anims
iOS2627Anims_FILES = Tweak.x
iOS2627Anims_CFLAGS = -fobjc-arc -Wall -Wextra
iOS2627Anims_FRAMEWORKS = UIKit QuartzCore CoreGraphics
# Debug builds export the Frida test hooks (autotest/, frida/shots); release (FINALPACKAGE=1) does not.
ifneq ($(FINALPACKAGE),1)
iOS2627Anims_CFLAGS += -DCG27_TEST_HOOKS=1
iOS2627Anims_FRAMEWORKS += ImageIO
endif
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += iOS2627AnimsPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
