TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = iOS27AnimsRebornPrefs
iOS27AnimsRebornPrefs_FILES = CG27RebornRootListController.m
iOS27AnimsRebornPrefs_INSTALL_PATH = /Library/PreferenceBundles
iOS27AnimsRebornPrefs_FRAMEWORKS = UIKit
iOS27AnimsRebornPrefs_PRIVATE_FRAMEWORKS = Preferences
iOS27AnimsRebornPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -fno-ptrauth-objc-class-ro
include $(THEOS_MAKE_PATH)/bundle.mk
