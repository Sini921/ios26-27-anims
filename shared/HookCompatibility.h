#pragma once

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#ifndef CG27_TESTING
#include <substrate.h>
#endif

typedef struct { double topLeft, bottomLeft, bottomRight, topRight; } CG27CornerRadii;

// Private selectors can disappear or change ABI between SpringBoard versions.
// In particular, installing an absent selector can leave Logos' %orig NULL.
typedef struct {
    const char *selector;
    const char *types[5]; // Return type, followed by explicit argument types.
} CG27HookSignature;

static NSString *CG27CanonicalType(const char *type) {
    if (!type) return nil;
    NSMutableString *result = [NSMutableString string];
    for (const char *p = type; *p; p++) {
        if (*p == '"') {
            while (p[1] && p[1] != '"') p++;
            if (p[1]) p++;
            continue;
        }
        if (*p == '{' || *p == '(') {
            char end = *p == '{' ? '}' : ')';
            [result appendFormat:@"%c", *p];
            while (p[1] && p[1] != '=' && p[1] != end) p++;
            continue;
        }
        if (strchr("rnNoORV", *p)) continue;
        // Blocks and objects use the same calling convention here.
        if (*p == '?' && p > type && p[-1] == '@') continue;
        [result appendFormat:@"%c", *p];
    }
    return result;
}

static BOOL CG27MethodMatches(Method method, const CG27HookSignature *signature) {
    if (!method || !signature) return NO;
    unsigned int count = 0;
    while (count < 5 && signature->types[count]) count++;
    if (!count || method_getNumberOfArguments(method) != count + 1) return NO;
    for (unsigned int i = 0; i < count; i++) {
        char *actual = i == 0 ? method_copyReturnType(method) : method_copyArgumentType(method, i + 1);
        // The launch hook has only void/object types. Keep that early path
        // entirely in C, before Foundation and UIKit have finished startup.
        BOOL matches = actual && (!strcmp(actual, signature->types[i]) ||
            [CG27CanonicalType(actual) isEqualToString:CG27CanonicalType(signature->types[i])]);
        free(actual);
        if (!matches) return NO;
    }
    return YES;
}

static const CG27HookSignature *CG27SignatureForSelector(SEL selector) {
    static const CG27HookSignature signatures[] = {
        {"applicationDidFinishLaunching:", {@encode(void), @encode(id)}},
        {"setAccessoryBrightness:", {@encode(void), @encode(CGFloat)}},
        {"layoutSettingsForTargetCenter:", {@encode(id), @encode(CGPoint)}},
        {"transitionWillBegin", {@encode(id)}},
        {"handleTimerEvent:", {@encode(id), @encode(id)}},
        {"cornerRadiiForIndex:", {@encode(CG27CornerRadii), @encode(NSUInteger)}},
        {"transitionWillUpdate", {@encode(id)}},
        {"initWithAppLayout:gestureEdge:liftOffVelocity:", {@encode(id), @encode(id), @encode(NSUInteger), @encode(CGPoint)}},
        {"animationAttributesForLayoutElement:", {@encode(id), @encode(id)}},
        {"setDefaultValues", {@encode(void)}},
        {"_layoutSettings", {@encode(id)}},
        {"_positionSettings", {@encode(id)}},
        {"_scaleSettings", {@encode(id)}},
        {"_settingsByInterpolatingBetween:and:progress:", {@encode(id), @encode(id), @encode(id), @encode(double)}},
        {"sameWallpaperInitialTransitionSettings", {@encode(id)}},
        {"sameWallpaperSubsequentTransitionSettings", {@encode(id)}},
        {"differentWallpaperInitialTransitionSettings", {@encode(id)}},
        {"differentWallpaperSubsequentTransitionSettings", {@encode(id)}},
        {"overAppTransitionSettings", {@encode(id)}},
        {"iconsFlyIn", {@encode(BOOL)}},
        {"coverSheetSlidingViewController:prepareForPresentationTransitionForUserGesture:", {@encode(void), @encode(id), @encode(BOOL)}},
        {"coverSheetSlidingViewController:prepareForDismissalTransitionForReversingTransition:forUserGesture:", {@encode(void), @encode(id), @encode(BOOL), @encode(BOOL)}},
        {"coverSheetSlidingViewController:committingToEndPresented:", {@encode(void), @encode(id), @encode(BOOL)}},
        {"coverSheetSlidingViewControllerDidEndTransition:", {@encode(void), @encode(id)}},
        {"_cleanupATransition", {@encode(void)}},
        {"_itemContainerForAppLayoutIfExists:", {@encode(id), @encode(id)}},
        {"_performModifierMatchMoveToIconViewResponse:", {@encode(void), @encode(id)}},
        {"_iconImageFrameForIconView:", {@encode(CGRect), @encode(id)}},
        {"layoutSubviews", {@encode(void)}},
        {"didMoveToSuperview", {@encode(void)}},
        {"setHidden:forReason:withAnimationSettings:", {@encode(void), @encode(BOOL), @encode(id), @encode(id)}},
        {"setValue:forKey:", {@encode(void), @encode(id), @encode(id)}},
        {"_presentGestureBeganWithGestureRecognizer:", {@encode(void), @encode(id)}},
        {"_dismissGestureBeganWithGestureRecognizer:", {@encode(void), @encode(id)}},
        {"_startCatchupAnimationWithDuration:completion:", {@encode(void), @encode(double), @encode(id)}},
        {"listMinY", {@encode(double)}},
        {"horizontalInsetMargin", {@encode(double)}},
        {"setBounds:", {@encode(void), @encode(CGRect)}},
        {"_iconForWorkspaceEntity:", {@encode(id), @encode(id)}},
        {"homeScreenIconCornerRadiusForAppLayout:", {@encode(double), @encode(id)}},
    };
    const char *name = sel_getName(selector);
    for (size_t i = 0; i < sizeof(signatures) / sizeof(signatures[0]); i++)
        if (!strcmp(name, signatures[i].selector)) return &signatures[i];
    return NULL;
}

static void CG27HookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!CG27MethodMatches(method, CG27SignatureForSelector(selector))) {
        fprintf(stderr, "[iOS27Animations] Skipping incompatible hook %s %s (runtime: %s)\n",
              cls ? class_getName(cls) : "<missing class>", sel_getName(selector),
              method ? method_getTypeEncoding(method) : "<missing method>");
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

// Logos-generated calls below this include use the checked installer.
#define MSHookMessageEx CG27HookMessageEx
