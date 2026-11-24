TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = iOS2627AnimsPrefs
iOS2627AnimsPrefs_FILES = CG27RootListController.m
iOS2627AnimsPrefs_INSTALL_PATH = /Library/PreferenceBundles
iOS2627AnimsPrefs_FRAMEWORKS = UIKit
iOS2627AnimsPrefs_PRIVATE_FRAMEWORKS = Preferences
iOS2627AnimsPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -fno-ptrauth-objc-class-ro
include $(THEOS_MAKE_PATH)/bundle.mk
