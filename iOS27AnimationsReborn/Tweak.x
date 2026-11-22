#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/stat.h>
#include <os/lock.h>
#include "SpringMath.h"
#include "GenieEngine.h"

@interface SBFFluidBehaviorSettings : NSObject <NSCopying>
@property (nonatomic) double dampingRatio;
@property (nonatomic) double response;
@property (nonatomic) double retargetImpulse;
- (unsigned int)highFrameRateReason;
- (CAFrameRateRange)frameRateRange API_AVAILABLE(ios(15.0));
- (void)setFrameRateRange:(CAFrameRateRange)range highFrameRateReason:(unsigned int)reason API_AVAILABLE(ios(15.0));
@end

@interface CADisplayLink (CG27Private)
- (void)setHighFrameRateReason:(unsigned int)reason;
@end

static const unsigned int kCG27DefaultFrameRateReason = 0x110001;
static unsigned int gCG27FrameRateReason = kCG27DefaultFrameRateReason;

static void CG27RequestHighFrameRate(CADisplayLink *link, unsigned int reason) {
    if (@available(iOS 15.0, *)) link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    if ([link respondsToSelector:@selector(setHighFrameRateReason:)])
        [link setHighFrameRateReason:reason ?: kCG27DefaultFrameRateReason];
}

@interface SBTransitionSwitcherModifier : NSObject
@end

@interface SBFullScreenToHomeIconZoomSwitcherModifier : SBTransitionSwitcherModifier
- (CGRect)frameForIndex:(NSUInteger)index;
- (BOOL)_isIndexZoomAppLayout:(NSUInteger)index;
- (id)layoutSettingsForTargetCenter:(CGPoint)center;
@end

@interface SBChainableModifierEventResponse : NSObject
+ (id)responseByAppendingResponse:(id)response toResponse:(id)toResponse;
@end
@interface SBSwitcherModifierEventResponse : SBChainableModifierEventResponse
@end
@interface SBTimerEventSwitcherEventResponse : SBSwitcherModifierEventResponse
- (instancetype)initWithDelay:(double)delay validator:(BOOL (^)(void))validator reason:(NSString *)reason;
@end
@interface SBUpdateLayoutSwitcherEventResponse : SBSwitcherModifierEventResponse
- (instancetype)initWithOptions:(NSUInteger)options updateMode:(NSInteger)updateMode;
@end
@interface SBTimerSwitcherModifierEvent : NSObject
@property (nonatomic, readonly) NSString *reason;
@end

@interface SBFluidSwitcherViewController : UIViewController
- (UIView *)_itemContainerForAppLayoutIfExists:(id)appLayout;
- (UIView *)iconViewForAppLayout:(id)appLayout;
- (CGRect)_iconImageFrameForIconView:(UIView *)iconView;
@end
@interface NSObject (CG27IconView)
- (CGRect)iconImageFrame;
@end
@interface NSObject (CG27WidgetSource)
- (id)objectForActivationSetting:(NSUInteger)setting;
- (BOOL)isDeviceApplicationSceneEntity;
- (id)deviceApplicationSceneEntity;
- (id)sceneHandle;
- (NSString *)lastActivationIconLeafIdentifier;
- (BOOL)isWidgetIcon;
- (NSUInteger)gridSizeClass;
- (NSString *)leafIdentifier;
@end
static int gCG27StockIconFrame;

@interface UIView (CG27ItemIdentity)
- (id)appLayout;
@end

typedef struct { CGFloat x, y; } CG27MeshPoint;
typedef struct { CGFloat x, y, z; } CG27MeshPoint3D;
typedef struct { CG27MeshPoint from; CG27MeshPoint3D to; } CG27MeshVertex;
typedef struct { unsigned int indices[4]; float w[4]; } CG27MeshFace;
@interface CAMutableMeshTransform : NSObject
+ (instancetype)meshTransform;
- (void)addVertex:(CG27MeshVertex)vertex;
- (void)addFace:(CG27MeshFace)face;
@property (nonatomic) NSInteger subdivisionSteps;
@end
@interface CALayer (CG27Mesh)
- (void)setMeshTransform:(id)mesh;
@end

@interface UIViewFloatAnimatableProperty : NSObject
@property (nonatomic) double value;
@property (nonatomic, readonly) double presentationValue;
- (void)invalidate;
- (BOOL)isInvalidated;
@end
@interface UIView (CG27InProcess)
+ (void)_createTransformerWithInputAnimatableProperties:(NSArray *)properties modelValueSetter:(void (^)(void))model
                                 presentationValueSetter:(void (^)(void))presentation;
- (void)_setPresentationValue:(id)value forKey:(NSString *)key;
- (void)stopSettingPresentationValueForKey:(NSString *)key;
+ (BOOL)_isInAnimationBlock;
+ (void)sb_animateWithSettings:(id)settings mode:(NSInteger)mode animations:(void (^)(void))animations completion:(id)completion;
@end
@interface SBFFluidBehaviorSettings (CG27Defaults)
- (instancetype)initWithDefaultValues;
@end

typedef struct { double topLeft, bottomLeft, bottomRight, topRight; } CG27CornerRadii;
@interface SBFullScreenToHomeIconZoomSwitcherModifier (CG27Radii)
- (CG27CornerRadii)cornerRadiiForIndex:(NSUInteger)index;
@end

extern float UIAnimationDragCoefficient(void);

static double gCG27PrefsLoaded = -1;

static CFPropertyListRef CG27CopyPref(CFStringRef key) {
    static CFMutableDictionaryRef cache;
    double now = CACurrentMediaTime();
    if (!cache) cache = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (gCG27PrefsLoaded < 0 || now - gCG27PrefsLoaded > 0.5) { CFDictionaryRemoveAllValues(cache); gCG27PrefsLoaded = now; }
    CFPropertyListRef v = CFDictionaryGetValue(cache, key);
    if (!v) {
        v = CFPreferencesCopyAppValue(key, CFSTR("com.bazik1337.ios27animsreborn"));
        CFDictionarySetValue(cache, key, v ?: (CFPropertyListRef)kCFNull);
        if (v) CFRelease(v);
        v = CFDictionaryGetValue(cache, key);
    }
    return v == (CFPropertyListRef)kCFNull ? NULL : CFRetain(v);
}

static BOOL CG27BoolPref(CFStringRef key, BOOL fallback) {
    CFPropertyListRef v = CG27CopyPref(key);
    if (!v) return fallback;
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue((CFBooleanRef)v) : fallback;
    CFRelease(v);
    return on;
}

static BOOL CG27Enabled(void) {
    if (UIAccessibilityIsReduceMotionEnabled()) return NO;
    return CG27BoolPref(CFSTR("Enabled"), NO);
}

static BOOL CG27AppEnabled(void) {
    return CG27Enabled() && CG27BoolPref(CFSTR("AppAnimations"), YES);
}

static NSUInteger CG27UIntIvar(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return NSNotFound;
    const char *type = ivar_getTypeEncoding(iv);
    if (!type || (strcmp(type, @encode(NSUInteger)) && strcmp(type, @encode(NSInteger)))) return NSNotFound;
    return *(NSUInteger *)((uint8_t *)(__bridge void *)obj + ivar_getOffset(iv));
}

@interface NSObject (CG27IconGridClass)
- (NSUInteger)homeScreenIconGridSizeClassForAppLayout:(id)appLayout;
@end
static NSUInteger CG27IconGridClass(id modifier, id appLayout) {
    if (!appLayout) {
        Ivar iv = class_getInstanceVariable(object_getClass(modifier), "_appLayout");
        if (iv && ivar_getTypeEncoding(iv)[0] == '@') appLayout = object_getIvar(modifier, iv);
    }
    if (appLayout && [modifier respondsToSelector:@selector(homeScreenIconGridSizeClassForAppLayout:)]) {
        NSUInteger sizeClass = [modifier homeScreenIconGridSizeClassForAppLayout:appLayout];
        if (sizeClass <= 4) return sizeClass;
    }
    NSUInteger stored = CG27UIntIvar(modifier, "_iconGridSizeClass");
    return stored <= 4 ? stored : NSNotFound;
}
static double CG27GenieScaleForTarget(id modifier, id appLayout, CGRect icon) {
    NSUInteger sizeClass = CG27IconGridClass(modifier, appLayout);
    return sizeClass != NSNotFound ? G27GenieScaleForGridClass(sizeClass) :
        G27GenieScaleForIcon(icon.size.width, icon.size.height, UIScreen.mainScreen.bounds.size.width);
}
static BOOL CG27IsWidgetTarget(id modifier) {
    NSUInteger sizeClass = CG27IconGridClass(modifier, nil);
    if (sizeClass != NSNotFound) return sizeClass >= 1;
    Ivar iv = class_getInstanceVariable(object_getClass(modifier), "_homeScreenIconFrame");
    NSUInteger size = 0;
    if (iv) NSGetSizeAndAlignment(ivar_getTypeEncoding(iv), &size, NULL);
    if (!iv || size != sizeof(CGRect) || strncmp(ivar_getTypeEncoding(iv), "{CGRect=", 8)) return NO;
    CGRect icon = *(CGRect *)((uint8_t *)(__bridge void *)modifier + ivar_getOffset(iv));
    return G27GenieScaleForIcon(icon.size.width, icon.size.height, UIScreen.mainScreen.bounds.size.width) != 0.4;
}

static double CG27SlowFactor(void) {
    return 1.0;
}

static const double kOpenDampingRatio = 1.0;
static const double kOpenResponse = 0.24;

static double CG27OpenResponse(void) {
    return kOpenResponse;
}

static double CG27CloseScale(void) {
    return 1.0;
}

static BOOL CG27DropletEnabled(void) {
    return YES;
}
static const double kCloseResponse = 0.336;

static NSString *const kCG27CornerResetReason = @"iOS27AnimsRebornCornerRadiusReset";
static const double kOpenCornerResetDelay = 0.06;
static const double kCloseCornerResetDelay = 0.12;
static const NSUInteger kPhaseWillUpdate = 2;
static const void *kCG27CornerResetKey = &kCG27CornerResetKey;
static const void *kCG27StartedKey = &kCG27StartedKey;
static const void *kCG27GlassBeginKey = &kCG27GlassBeginKey;
static const BOOL kCG27GlassRimEnabled = NO;
static const BOOL kCG27OpeningShadeEnabled = NO;
static const BOOL kCG27SheetClockOffsetEnabled = NO;

static double CG27TimeScale(void) {
    double drag = UIAnimationDragCoefficient();
    return CG27SlowFactor() * (isfinite(drag) && drag > 0 ? drag : 1);
}

static double CG27Intensity(void);
static BOOL CG27GenieEnabled(void) {
    return CG27Intensity() > 0.001;
}

static __weak SBFluidSwitcherViewController *gCG27SwitcherVC;

static SBFluidSwitcherViewController *CG27SwitcherVC(void) {
    SBFluidSwitcherViewController *vc = gCG27SwitcherVC;
    if (vc) return vc;
    Class main = %c(SBMainSwitcherViewController);
    id shared = [main respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(main, @selector(sharedInstance)) : nil;
    SEL content = @selector(contentViewController);
    id candidate = [shared respondsToSelector:content] ? ((id (*)(id, SEL))objc_msgSend)(shared, content) : nil;
    if ([candidate isKindOfClass:%c(SBFluidSwitcherViewController)]) gCG27SwitcherVC = vc = candidate;
    return vc;
}

static double CG27Intensity(void) {
    return 1.0;
}

@interface CG27GenieDriver : NSObject {
@public
    G27Genie _engine;
    double _shownXY[G27_V][2];
    BOOL _hasShownXY;
    os_unfair_lock _nLock;
    UIView *_nContainer, *_nAccessory;
    NSArray<UIViewFloatAnimatableProperty *> *_nProps;
    double _nPx, _nMs, _nGs, _nGain;
    BOOL _nLive;
    unsigned int _nUpdating;
    double _nPrev[G27_V * 2 + 1], _nPrevTime;
    int _nCalls, _nMainCalls, _nLate;
    double _nCost, _nMaxCost, _nLastCall, _nMaxGap, _nFirstCall;
    int _nSuppressedModel, _nSuppressedPresentation;
}
@property (nonatomic) BOOL native;
@property (nonatomic) BOOL nativeActive;
@property (nonatomic, strong) id nativeMeshToken;
@property (nonatomic) CGRect icon;
@property (nonatomic) double genieScale;
@property (nonatomic) double response, zeta;
@property (nonatomic, strong) id layoutSettings;
@property (nonatomic, weak) UIView *container;
@property (nonatomic, weak) UIView *accessory;
@property (nonatomic) int accessorySearches;
@property (nonatomic, strong) id appLayout;
@property (nonatomic) double startTime, lastTime, intensity;
@property (nonatomic) BOOL sawLayout;
@property (nonatomic) double renderedB;
@property (nonatomic) BOOL retargeted;
@property (nonatomic) BOOL accessoryOverflows;
@property (nonatomic) BOOL iconFits;
@property (nonatomic, strong) NSHashTable<UIView *> *iconMeshViews;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, weak) id owner;
@property (nonatomic, strong) id previousMesh;
@property (nonatomic, strong) id appliedMesh;
@property (nonatomic, strong) CALayer *openingShade;
@property (nonatomic) double shadeStartTime;
@property (nonatomic, strong) CALayer *glassRim;
@property (nonatomic) double glassBeginTime;
@property (nonatomic, strong) NSHashTable<UIView *> *grabbers;
@property (nonatomic, strong) NSHashTable<UIView *> *movingGrabbers;
@property (nonatomic, strong) id movingGrabberToken;
@property (nonatomic) NSUInteger movingGrabberSearches;
@property (nonatomic, weak) UIView *badge;
@property (nonatomic, strong) UIView *badgeCopy;
@property (nonatomic) int badgeSearches;
@property (nonatomic) double iconWidth;
@property (nonatomic) BOOL opening;
- (void)finish;
- (void)start;
- (void)nativeSetUpWithContainer:(UIView *)container targetActive:(BOOL)targetActive;
- (void)nativeLoadEngine:(BOOL)active;
- (void)restoreMovingGrabbers;
- (void)nativeBounds:(CGRect)bounds of:(UIView *)container;
@end

static NSMutableArray<CG27GenieDriver *> *gCG27Genies;
static CG27GenieDriver *gCG27Genie;

static BOOL CG27SameFrame(CALayer *a, CALayer *b) {
    CGPoint p = a.position, q = b.position;
    CGSize s = a.bounds.size, t = b.bounds.size;
    if (fabs(p.x - q.x) >= 0.5 || fabs(p.y - q.y) >= 0.5 || fabs(s.width - t.width) >= 0.5 ||
        fabs(s.height - t.height) >= 0.5) return NO;
    CATransform3D ta = a.transform, tb = b.transform;
    const CGFloat *x = (const CGFloat *)&ta, *y = (const CGFloat *)&tb;
    for (int i = 0; i < 16; i++)
        if (!isfinite(x[i]) || !isfinite(y[i]) || fabs(x[i] - y[i]) > 1e-6) return NO;
    return YES;
}

static UIView *CG27FindAccessory(UIView *container) {
    static Class cls;
    if (!cls) cls = NSClassFromString(@"SBFluidSwitcherSpaceOverlayAccessoryView");
    if (!cls || !container.superview) return nil;
    for (UIView *v in container.superview.subviews)
        if ([v isKindOfClass:cls] && !v.hidden && CG27SameFrame(v.layer, container.layer) &&
            ![v.layer valueForKey:@"meshTransform"])
            return v;
    return nil;
}

static const void *kCG27CrossfadeScaleKey = &kCG27CrossfadeScaleKey;
static void CG27NormalizeCrossfadeScale(UIView *view) {
    NSArray *saved = objc_getAssociatedObject(view, kCG27CrossfadeScaleKey);
    BOOL foundIcon = NO, usable = YES;
    UIView *overlay = nil;
    double scale = 1;
    for (UIView *p = view.superview; p; p = p.superview) {
        if ([p isKindOfClass:%c(SBFluidSwitcherIconOverlayView)]) { overlay = p; break; }
        if ([p isKindOfClass:%c(SBIconView)]) foundIcon = YES;
        CATransform3D t = p.layer.transform;
        double sx = hypot(t.m11, t.m12), sy = hypot(t.m21, t.m22);
        if (!CATransform3DIsAffine(t) || !isfinite(sx) || !isfinite(sy) || fabs(sx - sy) > 1e-3 || sx <= 0 || !isfinite(1 / sx)) {
            usable = NO; break;
        }
        scale *= sx;
    }
    if (overlay && overlay.bounds.size.width > 1) scale *= view.bounds.size.width / overlay.bounds.size.width;
    else usable = NO;
    BOOL normalize = CG27AppEnabled() && foundIcon && overlay && usable &&
        isfinite(scale) && scale > 0 && isfinite(1 / scale) && fabs(scale - 1) > 1e-3;
    CATransform3D current = view.layer.transform;
    if (!normalize) {
        if (saved) {
            if (CATransform3DEqualToTransform(current, [saved[1] CATransform3DValue])) {
                [CATransaction begin]; [CATransaction setDisableActions:YES];
                view.layer.transform = [saved[0] CATransform3DValue];
                [CATransaction commit];
            }
            objc_setAssociatedObject(view, kCG27CrossfadeScaleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    CATransform3D base = saved && CATransform3DEqualToTransform(current, [saved[1] CATransform3DValue])
        ? [saved[0] CATransform3DValue] : current;
    CATransform3D adjusted = CATransform3DScale(base, 1 / scale, 1 / scale, 1);
    objc_setAssociatedObject(view, kCG27CrossfadeScaleKey,
        @[[NSValue valueWithCATransform3D:base], [NSValue valueWithCATransform3D:adjusted]], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    view.layer.transform = adjusted;
    [CATransaction commit];
}

static void CG27NormalizeAccessoryIcons(UIView *view, int depth) {
    if (!view || depth > 12) return;
    if ([view isKindOfClass:%c(SBIconImageCrossfadeView)]) { CG27NormalizeCrossfadeScale(view); return; }
    for (UIView *sub in view.subviews) CG27NormalizeAccessoryIcons(sub, depth + 1);
}

%hook SBFluidSwitcherIconOverlayView
- (void)layoutSubviews {
    %orig;
    CG27NormalizeAccessoryIcons((UIView *)self, 0);
}
%end

%hook SBIconImageCrossfadeView
- (void)didMoveToSuperview {
    %orig;
    CG27NormalizeCrossfadeScale((UIView *)self);
}
%end

static NSArray<UIView *> *CG27OverflowingIcons(UIView *accessory, BOOL *sawIcon) {
    CGRect bounds = CGRectInset(accessory.bounds, -1.5, -1.5);
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [accessory.subviews mutableCopy];
    for (int visited = 0; stack.count && visited < 200; visited++) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        CALayer *shown = v.layer.presentationLayer ?: v.layer;
        if (v.hidden || shown.opacity < 0.01) continue;
        NSString *name = NSStringFromClass(v.class);
        if ([name containsString:@"Badge"]) continue;
        if ([name containsString:@"IconImage"] && v.bounds.size.width > 1) {
            if (sawIcon) *sawIcon = YES;
            if (!CGRectContainsRect(bounds, [v convertRect:v.bounds toView:accessory])) [found addObject:v];
            continue;
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return found;
}

static id CG27GestureLayoutSettings(id appLayout);
static void CG27EnsureIOS27Settings(id modifier);

static NSString *const kCG27GrabberHideKey = @"iOS27AnimsRebornGrabberHide";

static void CG27CollectViews(UIView *v, NSString *className, int depth, NSHashTable<UIView *> *out) {
    Class cls = NSClassFromString(className);
    if (!cls || depth > 14) return;
    if ([v isKindOfClass:cls]) { [out addObject:v]; return; }
    for (UIView *sub in v.subviews) CG27CollectViews(sub, className, depth + 1, out);
}

static void CG27HideGrabbers(NSHashTable<UIView *> *grabbers) {
    for (UIView *g in grabbers) {
        if ([g.layer animationForKey:kCG27GrabberHideKey]) continue;
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
        a.fromValue = @0; a.toValue = @0; a.duration = 1e6;
        a.removedOnCompletion = NO;
        [g.layer addAnimation:a forKey:kCG27GrabberHideKey];
    }
}

static void CG27ShowGrabbers(NSHashTable<UIView *> *grabbers) {
    for (UIView *g in grabbers) {
        if (![g.layer animationForKey:kCG27GrabberHideKey]) continue;
        if ([g isKindOfClass:%c(SBIconBadgeView)]) {
            [g.layer removeAnimationForKey:kCG27GrabberHideKey];
            continue;
        }
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
        a.fromValue = @0; a.duration = 0.2;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [g.layer addAnimation:a forKey:kCG27GrabberHideKey];
    }
}

@interface UIView (CG27MovingGrabber)
- (void)setHidden:(BOOL)hidden forReason:(id)reason withAnimationSettings:(id)settings;
@end
static NSString *const kCG27FluidGrabberReason = @"FluidSwitcherHomeGrabberHideReason";
static const void *kCG27MovingGrabberOwnerKey = &kCG27MovingGrabberOwnerKey;
static const void *kCG27MovingGrabberRequestedKey = &kCG27MovingGrabberRequestedKey;
static NSUInteger gCG27MovingGrabberInternal;
static NSString *const kCG27MovingGrabberOpacityKey = @"CG27MovingGrabberOpacity";

static BOOL CG27GrabberInAccessory(UIView *view) {
    for (NSUInteger depth = 0; view && depth < 12; depth++, view = view.superview)
        if ([view isKindOfClass:%c(SBFluidSwitcherSpaceOverlayAccessoryView)]) return YES;
    return NO;
}
static void CG27WriteMovingGrabberHidden(UIView *view, BOOL hidden) {
    gCG27MovingGrabberInternal++;
    @try {
        [view setHidden:hidden forReason:kCG27FluidGrabberReason withAnimationSettings:nil];
    } @finally { gCG27MovingGrabberInternal--; }
}
%hook SBHomeGrabberView
- (void)setHidden:(BOOL)hidden forReason:(id)reason withAnimationSettings:(id)settings {
    if (NSThread.isMainThread && !gCG27MovingGrabberInternal && [reason isEqual:kCG27FluidGrabberReason] &&
        CG27GrabberInAccessory((UIView *)self)) {
        objc_setAssociatedObject(self, kCG27MovingGrabberRequestedKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (objc_getAssociatedObject(self, kCG27MovingGrabberOwnerKey)) hidden = NO;
    }
    %orig(hidden, reason, settings);
}
%end

static const void *kCG27MeshScaleKey = &kCG27MeshScaleKey;
static void CG27SetMeshRenderScale(CALayer *layer) {
    CALayer *P = layer.presentationLayer ?: layer;
    CGRect b = P.bounds, s = [P convertRect:b toLayer:nil];
    if (b.size.width < 1 || b.size.height < 1) return;
    double screen = UIScreen.mainScreen.scale;
    double k = fmax(s.size.width / b.size.width, s.size.height / b.size.height) * screen;
    if (!isfinite(k)) return;
    k = fmin(fmax(ceil(k * 4) / 4, screen), 4 * screen);
    if (!objc_getAssociatedObject(layer, kCG27MeshScaleKey))
        objc_setAssociatedObject(layer, kCG27MeshScaleKey, @[@(layer.rasterizationScale), @(layer.contentsScale)],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (fabs(layer.rasterizationScale - k) > 0.01) layer.rasterizationScale = k;
    if (fabs(layer.contentsScale - k) > 0.01) layer.contentsScale = k;
}
static void CG27RestoreMeshRenderScale(CALayer *layer) {
    NSArray<NSNumber *> *stock = objc_getAssociatedObject(layer, kCG27MeshScaleKey);
    if (stock.count != 2) return;
    layer.rasterizationScale = stock[0].doubleValue;
    layer.contentsScale = stock[1].doubleValue;
    objc_setAssociatedObject(layer, kCG27MeshScaleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static const int kCG27PredictFrames = 8;
static NSString *const kCG27MeshAnimationKey = @"iOS27AnimsRebornMesh";

static CAGradientLayer *CG27GlassEdge(NSArray *colors) {
    CAGradientLayer *edge = [CAGradientLayer layer];
    edge.colors = colors;
    edge.locations = @[@0, @0.5, @1];
    edge.startPoint = CGPointMake(0.5, 0);
    edge.endPoint = CGPointMake(0.5, 1);
    CALayer *outline = [CALayer layer];
    outline.borderColor = UIColor.whiteColor.CGColor;
    edge.mask = outline;
    return edge;
}

static double CG27BoundsProgress(CGSize size) {
    CGSize screen = UIScreen.mainScreen.bounds.size;
    double H = screen.height, w = size.width, h = size.height;
    if (!(w > 1 && H > w + 1 && h > w - 1 && h < H + 1 && fabs(w - screen.width) < 1)) return NAN;
    return G27Clamp((H - h) / (H - w), 0, 1);
}

static BOOL CG27NativeGenieEnabled(void) {
    return %c(UIViewFloatAnimatableProperty) &&
        [UIView respondsToSelector:@selector(_createTransformerWithInputAnimatableProperties:modelValueSetter:presentationValueSetter:)] &&
        [UIView instancesRespondToSelector:@selector(_setPresentationValue:forKey:)] &&
        [UIView respondsToSelector:@selector(sb_animateWithSettings:mode:animations:completion:)] &&
        [%c(SBFFluidBehaviorSettings) instancesRespondToSelector:@selector(initWithDefaultValues)];
}

static const void *kCG27NativeMeshOwnerKey = &kCG27NativeMeshOwnerKey;
static void CG27ClaimNativeMesh(UIView *container, id token) {
    CALayer *layer = container.layer;
    if (!layer || !token || objc_getAssociatedObject(layer, kCG27NativeMeshOwnerKey) == token) return;
    objc_setAssociatedObject(layer, kCG27NativeMeshOwnerKey, token, OBJC_ASSOCIATION_RETAIN);
    [layer removeAnimationForKey:@"meshTransform"];
}

%hook CALayer
- (void)setValue:(id)value forKey:(NSString *)key {
    if ([key isEqualToString:@"meshTransform"] && objc_getAssociatedObject(self, kCG27NativeMeshOwnerKey)) return;
    %orig;
}
%end

@implementation CG27GenieDriver

- (void)updateGlassRim {
    if (!self.glassRim) return;
    UIView *parent = self.accessory ?: self.container;
    if (!parent) return;
    CALayer *root = self.glassRim;
    if (root.superlayer != parent.layer) [parent.layer addSublayer:root];
    CALayer *P = parent.layer.presentationLayer ?: parent.layer;
    CGFloat scale = hypot(P.transform.m11, P.transform.m12);
    if (!isfinite(scale) || scale < 0.05) scale = 1;
    CGSize size = P.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    CGFloat visualWidth = size.width * scale;
    CGFloat iconWidth = self.iconWidth > 1 ? self.iconWidth : 64;
    CGFloat fullWidth = UIScreen.mainScreen.bounds.size.width;
    CGFloat phase = G27Clamp((visualWidth - 2 * iconWidth) / fmax(fullWidth - 2 * iconWidth, 1), 0, 1);
    CGFloat radius = MIN(size.width, size.height) * (0.22 + 0.28 * phase);
    CGFloat stroke = fmin(fmax(0.75 / scale, 0.75), 8);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    root.bounds = (CGRect){CGPointZero, size};
    root.position = CGPointMake(CGRectGetMidX(P.bounds), CGRectGetMidY(P.bounds));
    for (CAGradientLayer *edge in root.sublayers) {
        CGFloat lift = 0.5 / scale;
        edge.frame = CGRectMake(0, -lift, size.width, size.height + lift);
        edge.mask.frame = edge.bounds;
        edge.mask.cornerRadius = radius;
        edge.mask.borderWidth = stroke;
    }
    [CATransaction commit];
}

- (void)ensureGlassRimAt:(double)now {
    if (self.opening || !kCG27GlassRimEnabled) {
        [self.glassRim removeFromSuperlayer];
        self.glassRim = nil;
        return;
    }
    double drag = UIAnimationDragCoefficient();
    if (!isfinite(drag) || drag <= 0) drag = 1;
    if (now - (self.glassBeginTime > 0 ? self.glassBeginTime : self.startTime) < 0.125 * drag) return;
    if (self.glassRim) return;
    CALayer *rim = [CALayer layer];
    rim.name = @"CG27GlassRim";
    CGColorRef whiteTop = CGColorCreateCopyWithAlpha(UIColor.whiteColor.CGColor, 0.35);
    CGColorRef whiteMid = CGColorCreateCopyWithAlpha(UIColor.whiteColor.CGColor, 0.12);
    CGColorRef whiteEnd = CGColorCreateCopyWithAlpha(UIColor.whiteColor.CGColor, 0.02);
    [rim addSublayer:CG27GlassEdge(@[(__bridge id)whiteTop, (__bridge id)whiteMid, (__bridge id)whiteEnd])];
    CGColorRelease(whiteTop);
    CGColorRelease(whiteMid);
    CGColorRelease(whiteEnd);
    self.glassRim = rim;
    [self updateGlassRim];
}

- (void)restoreMovingGrabbers {
    for (UIView *view in self.movingGrabbers.allObjects) {
        if (objc_getAssociatedObject(view, kCG27MovingGrabberOwnerKey) != self.movingGrabberToken) continue;
        NSNumber *requested = objc_getAssociatedObject(view, kCG27MovingGrabberRequestedKey);
        objc_setAssociatedObject(view, kCG27MovingGrabberOwnerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view.layer removeAnimationForKey:kCG27MovingGrabberOpacityKey];
        if (requested) CG27WriteMovingGrabberHidden(view, requested.boolValue);
    }
    self.movingGrabbers = nil;
    self.movingGrabberToken = nil;
    self.movingGrabberSearches = 0;
}

- (void)start {
    self.startTime = self.lastTime = CACurrentMediaTime();
    if (self.link) return;
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    CG27RequestHighFrameRate(self.link, gCG27FrameRateReason);
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self restoreMovingGrabbers];
    [self.link invalidate];
    self.link = nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.container.layer removeAnimationForKey:kCG27MeshAnimationKey];
    [self.accessory.layer removeAnimationForKey:kCG27MeshAnimationKey];
    if (self.native) [self nativeStop];
    if (self.appliedMesh) self.container.layer.meshTransform = self.previousMesh;
    if (self.appliedMesh && !self.accessoryOverflows) self.accessory.layer.meshTransform = nil;
    for (UIView *icon in self.iconMeshViews.allObjects) {
        icon.layer.meshTransform = nil;
        CG27RestoreMeshRenderScale(icon.layer);
    }
    self.iconMeshViews = nil;
    self.appliedMesh = nil;
    self.previousMesh = nil;
    [self.openingShade removeFromSuperlayer];
    self.openingShade = nil;
    [self.glassRim removeFromSuperlayer];
    self.glassRim = nil;
    NSHashTable<UIView *> *show = [self.grabbers copy];
    for (CG27GenieDriver *other in gCG27Genies)
        if (other != self && other.link && other.grabbers) [show minusHashTable:other.grabbers];
    CG27ShowGrabbers(show);
    self.grabbers = nil;
    [self.badgeCopy removeFromSuperview];
    self.badgeCopy = nil;
    [CATransaction commit];
}

- (void)engine:(const G27Genie *)g xy:(double (*)[2])xy {
    G27GenieMesh(g, g->b, xy);
    double gain = self.intensity;
    if (gain != 1.0)
        for (int k = 0; k < G27_V; k++) {
            xy[k][0] = (double)(k % G27_N) / (G27_N - 1) + gain * (xy[k][0] - (double)(k % G27_N) / (G27_N - 1));
            xy[k][1] = (double)(k / G27_N) / (G27_N - 1) + gain * (xy[k][1] - (double)(k / G27_N) / (G27_N - 1));
        }
}

static id CG27MeshFromXY(double (*xy)[2]) {
    CAMutableMeshTransform *mesh = [%c(CAMutableMeshTransform) meshTransform];
    mesh.subdivisionSteps = -1;
    for (int i = 0; i < G27_N; i++) {
        for (int j = 0; j < G27_N; j++) {
            int k = i * G27_N + j;
            CG27MeshVertex vx = { {(double)j / (G27_N - 1), (double)i / (G27_N - 1)}, {xy[k][0], xy[k][1], 0} };
            [mesh addVertex:vx];
        }
    }
    for (unsigned int i = 0; i + 1 < G27_N; i++) {
        for (unsigned int j = 0; j + 1 < G27_N; j++) {
            unsigned int a = i * G27_N + j;
            CG27MeshFace face = { {a, a + 1, a + G27_N + 1, a + G27_N}, {0, 0, 0, 0} };
            [mesh addFace:face];
        }
    }
    return mesh;
}

- (id)meshForEngine:(const G27Genie *)g {
    double xy[G27_V][2];
    [self engine:g xy:xy];
    return CG27MeshFromXY(xy);
}

- (void)applyMeshWithLead:(double)lead at:(double)showTime frame:(double)frame {
    G27Genie ahead = _engine;
    if (lead > 0 && lead < 0.05) G27GenieStep(&ahead, lead);
    self.renderedB = ahead.b;
    id mesh = [self meshForEngine:&ahead];
    id accessoryMesh = mesh;
    [self engine:&ahead xy:_shownXY];
    _hasShownXY = YES;
    CAKeyframeAnimation *prediction = nil, *accessoryPrediction = nil;
    if (showTime > 0 && frame > 0.004 && frame < 0.034 && !G27GenieSettled(&ahead)) {
        int steps = (int)fmin(ceil(frame * 120 - 0.01), 2) * kCG27PredictFrames;
        double step = frame * kCG27PredictFrames / steps;
        NSMutableArray *values = [NSMutableArray arrayWithObject:mesh];
        NSMutableArray *accessoryValues = [NSMutableArray arrayWithObject:accessoryMesh];
        NSMutableArray *times = [NSMutableArray arrayWithObject:@0];
        G27Genie future = ahead;
        for (int i = 1; i <= steps; i++) {
            G27GenieStep(&future, step);
            [values addObject:[self meshForEngine:&future]];
            [accessoryValues addObject:values.lastObject];
            [times addObject:@((double)i / (steps + 1))];
        }
        [times addObject:@1];
        prediction = [CAKeyframeAnimation animationWithKeyPath:@"meshTransform"];
        prediction.values = values;
        prediction.keyTimes = times;
        prediction.calculationMode = kCAAnimationDiscrete;
        prediction.beginTime = showTime;
        prediction.duration = step * (steps + 1);
        prediction.removedOnCompletion = YES;
        accessoryPrediction = [prediction copy];
        accessoryPrediction.values = accessoryValues;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CALayer *layer = self.container.layer;
    layer.meshTransform = mesh;
    if (prediction) [layer addAnimation:prediction forKey:kCG27MeshAnimationKey];
    else [layer removeAnimationForKey:kCG27MeshAnimationKey];
    UIView *accessory = self.accessory;
    if (accessory && self.accessoryOverflows) {
        for (UIView *icon in self.iconMeshViews.allObjects) {
            icon.layer.meshTransform = [self meshForIcon:icon];
            CG27SetMeshRenderScale(icon.layer);
        }
    } else if (accessory && CG27SameFrame(accessory.layer, layer)) {
        accessory.layer.meshTransform = accessoryMesh;
        if (accessoryPrediction) [accessory.layer addAnimation:accessoryPrediction forKey:kCG27MeshAnimationKey];
        else [accessory.layer removeAnimationForKey:kCG27MeshAnimationKey];
    } else if (accessory) {
        [accessory.layer removeAnimationForKey:kCG27MeshAnimationKey];
        accessory.layer.meshTransform = nil;
        self.accessory = nil;
    }
    if (self.glassRim) {
        BOOL needsOwnMesh = self.glassRim.superlayer == self.accessory.layer && self.accessoryOverflows;
        self.glassRim.meshTransform = needsOwnMesh ? accessoryMesh : nil;
        if (needsOwnMesh && accessoryPrediction)
            [self.glassRim addAnimation:accessoryPrediction forKey:kCG27MeshAnimationKey];
        else
            [self.glassRim removeAnimationForKey:kCG27MeshAnimationKey];
    }
    self.appliedMesh = mesh;
    [CATransaction commit];
}

- (void)tick:(CADisplayLink *)link {
    double now = CACurrentMediaTime();
    if (!CG27AppEnabled() || !CG27GenieEnabled() || now - self.startTime > 2.0 * CG27TimeScale()) {
        [self finish];
        return;
    }
    if (!self.container) {
        self.container = [CG27SwitcherVC() _itemContainerForAppLayoutIfExists:self.appLayout];
        if (!self.container) { if (now - self.startTime > 0.2) [self finish]; return; }
        if (![self.container.layer respondsToSelector:@selector(setMeshTransform:)]) { [self finish]; return; }
        self.previousMesh = self.native ? nil : [self.container.layer valueForKey:@"meshTransform"];
        if (self.previousMesh) { [self finish]; return; }
        self.grabbers = [NSHashTable weakObjectsHashTable];
        CG27CollectViews(self.container, @"SBAppSwitcherPageShadowView", 0, self.grabbers);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CG27HideGrabbers(self.grabbers);
        [CATransaction commit];
    }
    if (!self.container.window) { [self finish]; return; }
    if (self.native) {
        os_unfair_lock_lock(&_nLock);
        if (!_nContainer && _nLive) _nContainer = self.container;
        BOOL same = _nContainer == self.container;
        os_unfair_lock_unlock(&_nLock);
        if (!same) { [self finish]; return; }
        CG27ClaimNativeMesh(self.container, self.nativeMeshToken);
    }
    if ([self.container respondsToSelector:@selector(appLayout)] &&
        ![[self.container appLayout] isEqual:self.appLayout]) { [self finish]; return; }
    if (!self.accessoryOverflows && !self.accessory && self.accessorySearches < 240) {
        self.accessorySearches++;
        self.accessory = CG27FindAccessory(self.container);
    }
    if (self.native && !self.opening && self.accessory && !self.movingGrabbers.count && self.movingGrabberSearches++ < 120) {
        NSHashTable<UIView *> *views = [NSHashTable weakObjectsHashTable];
        CG27CollectViews(self.accessory, @"SBHomeGrabberView", 0, views);
        for (UIView *view in views.allObjects) {
            if (!objc_getAssociatedObject(view, kCG27MovingGrabberRequestedKey)) continue;
            if (!self.movingGrabbers) self.movingGrabbers = [NSHashTable weakObjectsHashTable];
            if (!self.movingGrabberToken) self.movingGrabberToken = [NSObject new];
            objc_setAssociatedObject(view, kCG27MovingGrabberOwnerKey, self.movingGrabberToken, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self.movingGrabbers addObject:view];
            CG27WriteMovingGrabberHidden(view, NO);
        }
    }
    if (self.accessory && !self.iconFits) {
        CG27NormalizeAccessoryIcons(self.accessory, 0);
        BOOL sawIcon = NO;
        NSArray<UIView *> *icons = CG27OverflowingIcons(self.accessory, &sawIcon);
        if (icons.count) [self meshIcons:icons];
        else if (sawIcon && !self.accessoryOverflows) self.iconFits = YES;
    }
    if (self.accessory && !self.badge && self.badgeSearches < 240) {
        self.badgeSearches++;
        NSHashTable<UIView *> *badges = [NSHashTable weakObjectsHashTable];
        CG27CollectViews(self.accessory, @"SBIconBadgeView", 0, badges);
        UIView *badge = nil;
        for (UIView *b in badges) if (!b.hidden && b.bounds.size.width > 1) { badge = b; break; }
        if (badge) {
            self.badge = badge;
            for (UIView *b in badges) [self.grabbers addObject:b];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            CG27HideGrabbers(self.grabbers);
            [CATransaction commit];
        }
    }
    if (self.badge && !self.badgeCopy && !self.opening) [self makeBadgeCopy];
    double dt = fmax(0, now - self.lastTime);
    self.lastTime = now;
    if (self.native) [self nativeSample:now];
    else [self advance:dt];
    if (!self.link) return;
    if (self.opening && self.shadeStartTime == 0 && _engine.b < 0.99) self.shadeStartTime = now;
    double shadeAge = self.shadeStartTime ? (now - self.shadeStartTime) / CG27TimeScale() : 0;
    double shadeAlpha = self.opening && self.shadeStartTime && shadeAge < 0.30 && kCG27OpeningShadeEnabled
        ? 0.62 * exp(-fmax(shadeAge - 0.06, 0) / 0.070) : 0;
    if (shadeAlpha > 0.008 && !self.openingShade) {
        CALayer *shade = [CALayer layer];
        shade.backgroundColor = UIColor.blackColor.CGColor;
        shade.opacity = 0;
        shade.frame = self.container.bounds;
        shade.masksToBounds = YES;
        CALayer *host = self.container.layer;
        for (UIView *v in self.container.subviews)
            if ([NSStringFromClass(v.class) containsString:@"ClippingView"]) { host = v.layer; break; }
        [host addSublayer:shade];
        self.openingShade = shade;
    }
    if (self.openingShade) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.openingShade.frame = self.container.bounds;
        self.openingShade.opacity = shadeAlpha;
        if (shadeAlpha <= 0.008) { [self.openingShade removeFromSuperlayer]; self.openingShade = nil; }
        [CATransaction commit];
    }
    [self ensureGlassRimAt:now];
    BOOL ownerRunning = self.owner && CG27UIntIvar(self.owner, "_transitionPhase") == kPhaseWillUpdate;
    if (G27GenieSettled(&_engine) && (!ownerRunning || now - self.startTime > 0.15)) { [self finish]; return; }
    BOOL tracking = self.sawLayout && self.owner &&
        CG27UIntIvar(self.owner, "_transitionPhase") == kPhaseWillUpdate;
    double frame = link.targetTimestamp - link.timestamp;
    if (!self.native) [self applyMeshWithLead:tracking ? frame : 0 at:link.targetTimestamp frame:frame];
    [self updateGlassRim];
    [self placeBadgeCopy];
}

- (void)meshIcons:(NSArray<UIView *> *)icons {
    if (!self.accessoryOverflows) {
        self.accessoryOverflows = YES;
        self.iconMeshViews = [NSHashTable weakObjectsHashTable];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self.accessory.layer removeAnimationForKey:kCG27MeshAnimationKey];
        self.accessory.layer.meshTransform = nil;
        [CATransaction commit];
    }
    for (UIView *icon in icons)
        if (![self.iconMeshViews containsObject:icon] && ![icon.layer valueForKey:@"meshTransform"])
            [self.iconMeshViews addObject:icon];
}

- (CGPoint)deformAccessoryPoint:(CGPoint)a {
    double gx = a.x * (G27_N - 1), gy = a.y * (G27_N - 1);
    int cj = (int)fmin(fmax(floor(gx), 0), G27_N - 2), ci = (int)fmin(fmax(floor(gy), 0), G27_N - 2);
    double u = gx - cj, v = gy - ci;
    const double *p00 = _shownXY[ci * G27_N + cj], *p01 = _shownXY[ci * G27_N + cj + 1];
    const double *p10 = _shownXY[(ci + 1) * G27_N + cj], *p11 = _shownXY[(ci + 1) * G27_N + cj + 1];
    return CGPointMake((1 - u) * (1 - v) * p00[0] + u * (1 - v) * p01[0] + (1 - u) * v * p10[0] + u * v * p11[0],
                       (1 - u) * (1 - v) * p00[1] + u * (1 - v) * p01[1] + (1 - u) * v * p10[1] + u * v * p11[1]);
}

- (id)meshForIcon:(UIView *)icon {
    UIView *acc = self.accessory;
    CALayer *AP = acc.layer.presentationLayer ?: acc.layer, *VP = icon.layer.presentationLayer ?: icon.layer;
    CGRect ab = AP.bounds, vb = VP.bounds;
    if (ab.size.width < 1 || ab.size.height < 1 || vb.size.width < 1 || vb.size.height < 1) return nil;
    static const int n = 5;
    CAMutableMeshTransform *mesh = [%c(CAMutableMeshTransform) meshTransform];
    mesh.subdivisionSteps = -1;
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            double s = (double)j / (n - 1), t = (double)i / (n - 1);
            CGPoint pa = [VP convertPoint:CGPointMake(vb.origin.x + s * vb.size.width, vb.origin.y + t * vb.size.height) toLayer:AP];
            CGPoint d = [self deformAccessoryPoint:CGPointMake((pa.x - ab.origin.x) / ab.size.width, (pa.y - ab.origin.y) / ab.size.height)];
            CGPoint qv = [AP convertPoint:CGPointMake(ab.origin.x + d.x * ab.size.width, ab.origin.y + d.y * ab.size.height) toLayer:VP];
            CG27MeshVertex vx = { {s, t}, {(qv.x - vb.origin.x) / vb.size.width, (qv.y - vb.origin.y) / vb.size.height, 0} };
            [mesh addVertex:vx];
        }
    }
    for (unsigned int i = 0; i + 1 < n; i++)
        for (unsigned int j = 0; j + 1 < n; j++) {
            unsigned int a = i * n + j;
            CG27MeshFace face = { {a, a + 1, a + n + 1, a + n}, {0, 0, 0, 0} };
            [mesh addFace:face];
        }
    return mesh;
}

- (void)makeBadgeCopy {
    UIView *badge = self.badge, *acc = self.accessory;
    if (!badge || !acc.superview || badge.bounds.size.width < 1) return;
    SEL snapshot = NSSelectorFromString(@"is18_transitionSnapshotView");
    if ([badge respondsToSelector:snapshot])
        self.badgeCopy = ((UIView *(*)(id, SEL))objc_msgSend)(badge, snapshot);
    if (!self.badgeCopy) {
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:badge.bounds];
        UIImage *image = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [badge.layer renderInContext:ctx.CGContext];
        }];
        self.badgeCopy = [[UIImageView alloc] initWithImage:image];
    }
    self.badgeCopy.userInteractionEnabled = NO;
    self.badgeCopy.layer.opacity = 0;
    [acc.superview insertSubview:self.badgeCopy aboveSubview:acc];
}

- (void)placeBadgeCopy {
    UIView *copy = self.badgeCopy, *badge = self.badge, *acc = self.accessory;
    if (!copy) return;
    if (self.opening || !badge || !acc || !_hasShownXY || !copy.superview) { copy.layer.opacity = 0; return; }
    CALayer *AP = acc.layer.presentationLayer ?: acc.layer, *SP = copy.superview.layer.presentationLayer ?: copy.superview.layer;
    CGRect ab = acc.bounds;
    CGRect r = [badge convertRect:badge.bounds toView:acc];
    const double *tr = _shownXY[G27_N - 1];
    CGPoint corner = CGPointMake(ab.origin.x + tr[0] * ab.size.width, ab.origin.y + tr[1] * ab.size.height);
    CGPoint o = CGPointMake(corner.x + (CGRectGetMinX(r) - CGRectGetMaxX(ab)), corner.y + (CGRectGetMinY(r) - CGRectGetMinY(ab)));
    CGPoint e = CGPointMake(o.x + r.size.width, o.y + r.size.height);
    CGPoint so = [AP convertPoint:o toLayer:SP], se = [AP convertPoint:e toLayer:SP];
    CGPoint a0 = [AP convertPoint:ab.origin toLayer:SP];
    CGPoint a1 = [AP convertPoint:CGPointMake(CGRectGetMaxX(ab), ab.origin.y) toLayer:SP];
    double shownW = hypot(a1.x - a0.x, a1.y - a0.y), iw = self.iconWidth > 1 ? self.iconWidth : 64;
    double alpha = fmin(fmax((2 * iw - shownW) / iw, 0), 1);
    for (UIView *v = badge.superview; v && alpha > 0; v = v.superview) {
        CALayer *P = v.layer.presentationLayer ?: v.layer;
        alpha *= P.opacity * (v.hidden ? 0 : 1);
        if (v == acc) break;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    copy.layer.bounds = badge.bounds;
    copy.layer.transform = CATransform3DMakeScale(fabs(se.x - so.x) / badge.bounds.size.width,
                                                fabs(se.y - so.y) / badge.bounds.size.height, 1);
    copy.layer.position = CGPointMake((so.x + se.x) / 2, (so.y + se.y) / 2);
    copy.layer.opacity = alpha;
    [CATransaction commit];
}

- (void)advance:(double)dt {
    CALayer *layer = self.container.layer.presentationLayer ?: self.container.layer;
    CGSize size = layer.bounds.size, screen = UIScreen.mainScreen.bounds.size;
    double H = screen.height, w = size.width, h = size.height;
    BOOL valid = w > 1 && H > w + 1 && h > w - 1 && h < H + 1 && fabs(w - screen.width) < 1;
    double bMeas = valid ? G27Clamp((H - h) / (H - w), 0, 1) : NAN;
    if (valid && !self.sawLayout) {
        if (!self.retargeted && _engine.bTarget == 0 && h > H - 0.5) return;
        else self.sawLayout = YES;
    }
    if (!valid) { G27GenieStep(&_engine, dt); return; }
    BOOL ownerRunning = self.owner && CG27UIntIvar(self.owner, "_transitionPhase") == kPhaseWillUpdate;
    if (!ownerRunning) G27GenieStep(&_engine, dt);
    else G27GenieFollowBounds(&_engine, bMeas, dt);
}

- (void)nativeLoadEngine:(BOOL)active {
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGRect icon = self.icon;
    G27GenieRetargetWithScale(&_engine, active, CGRectGetMidX(icon), CGRectGetMidY(icon), icon.size.width, screen.width, screen.height,
                              self.response, self.zeta, self.genieScale);
    os_unfair_lock_lock(&_nLock);
    _nPx = _engine.px; _nMs = _engine.ms; _nGs = _engine.gs; _nGain = self.intensity;
    os_unfair_lock_unlock(&_nLock);
}

- (void)nativeSetUpWithContainer:(UIView *)container targetActive:(BOOL)targetActive {
    _nLock = OS_UNFAIR_LOCK_INIT;
    self.nativeMeshToken = [NSObject new];
    CG27ClaimNativeMesh(container, self.nativeMeshToken);
    double b0 = container ? CG27BoundsProgress(container.bounds.size) : NAN;
    BOOL active0 = isfinite(b0) ? b0 > 0.5 : !targetActive;
    if (!isfinite(b0)) b0 = active0 ? 1 : 0;
    [self nativeLoadEngine:active0];
    self.nativeActive = active0;
    NSMutableArray<UIViewFloatAnimatableProperty *> *props = [NSMutableArray array];
    for (int i = 0; i < G27_V * 2 + 1; i++) [props addObject:[%c(UIViewFloatAnimatableProperty) new]];
    G27Genie *e = &_engine;
    [UIView performWithoutAnimation:^{
        for (int k = 0; k < G27_V; k++)
            for (int a = 0; a < 2; a++) {
                e->p[k][a] = e->target[k][a]; e->v[k][a] = 0;
                props[2 * k + a].value = e->target[k][a];
            }
        props.lastObject.value = b0;
    }];
    _engine.b = _engine.bTarget = b0; _engine.bv = 0;
    os_unfair_lock_lock(&_nLock);
    _nProps = [props copy];
    _nContainer = container;
    _nLive = YES;
    os_unfair_lock_unlock(&_nLock);
    __weak CG27GenieDriver *weakSelf = self;
    [UIView _createTransformerWithInputAnimatableProperties:props modelValueSetter:^{
        [weakSelf nativeUpdate:NO];
    } presentationValueSetter:^{
        [weakSelf nativeUpdate:YES];
    }];
}

- (void)nativePerform:(BOOL)active {
    self.nativeActive = active;
    [self nativeLoadEngine:active];
    NSArray<UIViewFloatAnimatableProperty *> *props = _nProps;
    if (props.count != G27_V * 2 + 1) return;
    for (int k = 0; k < G27_V; k++) {
        SBFFluidBehaviorSettings *spring = [[%c(SBFFluidBehaviorSettings) alloc] initWithDefaultValues];
        spring.dampingRatio = _engine.zeta;
        spring.response = _engine.response[k];
        if ([spring respondsToSelector:@selector(setRetargetImpulse:)]) spring.retargetImpulse = 0;
        UIViewFloatAnimatableProperty *x = props[2 * k], *y = props[2 * k + 1];
        double tx = _engine.target[k][0], ty = _engine.target[k][1];
        [UIView sb_animateWithSettings:spring mode:3 animations:^{
            x.value = tx;
            y.value = ty;
        } completion:nil];
    }
}

- (void)nativeBounds:(CGRect)bounds of:(UIView *)container {
    double b = CG27BoundsProgress(bounds.size);
    if (!isfinite(b)) return;
    os_unfair_lock_lock(&_nLock);
    if (!_nContainer && _nLive) _nContainer = container;
    BOOL mine = _nContainer == container;
    NSArray<UIViewFloatAnimatableProperty *> *props = _nProps;
    os_unfair_lock_unlock(&_nLock);
    if (!mine || props.count != G27_V * 2 + 1) return;
    CG27ClaimNativeMesh(container, self.nativeMeshToken);
    UIViewFloatAnimatableProperty *progress = props.lastObject;
    BOOL active = b > 0.5;
    BOOL changesDirection = active != self.nativeActive;
    BOOL changesBounds = fabs(progress.value - b) > 1e-6;
    if (!changesBounds && !changesDirection) return;
    if (changesDirection && active != !self.opening) {
        [self finish];
        return;
    }
    BOOL animated = [UIView areAnimationsEnabled] && [UIView respondsToSelector:@selector(_isInAnimationBlock)] &&
        [UIView _isInAnimationBlock];
    if (changesDirection && !animated) {
        [self finish];
        return;
    }
    os_unfair_lock_lock(&_nLock); _nUpdating++; os_unfair_lock_unlock(&_nLock);
    @try {
        if (changesBounds) progress.value = b;
        _engine.bTarget = b;
        if (changesDirection) [self nativePerform:active];
    } @finally {
        os_unfair_lock_lock(&_nLock); _nUpdating--; os_unfair_lock_unlock(&_nLock);
    }
    [self nativeUpdate:NO];
}

static void CG27NativeApplyMesh(UIView *view, id mesh, BOOL presentation) {
    if (presentation) { [view _setPresentationValue:mesh forKey:@"meshTransform"]; return; }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    view.layer.meshTransform = mesh;
    [CATransaction commit];
}

- (void)nativeUpdate:(BOOL)presentation {
    if (!presentation && !NSThread.isMainThread) return;
    os_unfair_lock_lock(&_nLock);
    if (_nUpdating) {
        os_unfair_lock_unlock(&_nLock);
        return;
    }
    if (_nLive && _nContainer && _nProps.count == G27_V * 2 + 1) {
        G27Genie g;
        g.px = _nPx; g.ms = _nMs; g.gs = _nGs;
        for (int k = 0; k < G27_V; k++)
            for (int a = 0; a < 2; a++) {
                UIViewFloatAnimatableProperty *p = _nProps[2 * k + a];
                g.p[k][a] = presentation ? p.presentationValue : p.value;
            }
        double b = presentation ? _nProps.lastObject.presentationValue : _nProps.lastObject.value;
        double xy[G27_V][2];
        G27GenieMesh(&g, b, xy);
        double gain = _nGain;
        if (gain != 1.0)
            for (int k = 0; k < G27_V; k++) {
                double gx = (double)(k % G27_N) / (G27_N - 1), gy = (double)(k / G27_N) / (G27_N - 1);
                xy[k][0] = gx + gain * (xy[k][0] - gx);
                xy[k][1] = gy + gain * (xy[k][1] - gy);
            }
        BOOL finite = YES;
        for (int k = 0; k < G27_V; k++) finite = finite && isfinite(xy[k][0]) && isfinite(xy[k][1]);
        if (finite) {
            id mesh = CG27MeshFromXY(xy);
            CG27NativeApplyMesh(_nContainer, mesh, presentation);
            if (_nAccessory) {
                CG27NativeApplyMesh(_nAccessory, mesh, presentation);
            }
        }
    }
    os_unfair_lock_unlock(&_nLock);
}

static void CG27NativeClearMesh(UIView *view, id modelMesh) {
    if (!view) return;
    if ([view respondsToSelector:@selector(stopSettingPresentationValueForKey:)])
        [view stopSettingPresentationValueForKey:@"meshTransform"];
    view.layer.meshTransform = modelMesh;
}

- (void)nativeSample:(double)now {
    NSArray<UIViewFloatAnimatableProperty *> *props = _nProps;
    if (props.count != G27_V * 2 + 1) return;
    double dt = now - _nPrevTime;
    BOOL first = _nPrevTime == 0 || dt <= 0;
    for (int i = 0; i < G27_V * 2 + 1; i++) {
        double value = props[i].presentationValue;
        double velocity = first ? 0 : (value - _nPrev[i]) / dt;
        _nPrev[i] = value;
        if (i < G27_V * 2) { _engine.p[i / 2][i % 2] = value; _engine.v[i / 2][i % 2] = velocity; }
        else { _engine.b = value; _engine.bv = velocity; _engine.bTarget = props[i].value; }
    }
    _nPrevTime = now;
    [self engine:&_engine xy:_shownXY];
    _hasShownXY = YES;
    self.renderedB = _engine.b;
    if (self.movingGrabbers.count) {
        NSMutableArray *alphas = [NSMutableArray array];
        double b = _engine.b, velocity = _engine.bv;
        for (int i = 0; i <= 4; i++) {
            [alphas addObject:@(G27ClosingSnapshotAlpha(b))];
            G27SpringStep(&b, &velocity, _engine.bTarget, _engine.bResponse, _engine.zeta, 1.0 / 120);
        }
        CAKeyframeAnimation *opacity = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        opacity.values = alphas; opacity.duration = 4.0 / 120; opacity.beginTime = now;
        opacity.fillMode = kCAFillModeBoth; opacity.removedOnCompletion = NO;
        for (UIView *view in self.movingGrabbers.allObjects)
            [view.layer addAnimation:opacity forKey:kCG27MovingGrabberOpacityKey];
    }

    UIView *accessory = self.accessory, *meshed = nil, *dropped = nil;
    if (accessory && !self.accessoryOverflows && CG27SameFrame(accessory.layer, self.container.layer)) meshed = accessory;
    os_unfair_lock_lock(&_nLock);
    if (_nAccessory != meshed) { dropped = _nAccessory; _nAccessory = meshed; }
    os_unfair_lock_unlock(&_nLock);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (dropped) CG27NativeClearMesh(dropped, nil);
    if (accessory && self.accessoryOverflows)
        for (UIView *icon in self.iconMeshViews.allObjects) {
            icon.layer.meshTransform = [self meshForIcon:icon];
            CG27SetMeshRenderScale(icon.layer);
        }
    [CATransaction commit];
}

- (void)nativeStop {
    os_unfair_lock_lock(&_nLock);
    _nLive = NO;
    UIView *container = _nContainer, *accessory = _nAccessory;
    NSArray<UIViewFloatAnimatableProperty *> *props = _nProps;
    _nContainer = _nAccessory = nil;
    _nProps = nil;
    os_unfair_lock_unlock(&_nLock);
    if (container && objc_getAssociatedObject(container.layer, kCG27NativeMeshOwnerKey) == self.nativeMeshToken)
        objc_setAssociatedObject(container.layer, kCG27NativeMeshOwnerKey, nil, OBJC_ASSOCIATION_RETAIN);
    self.nativeMeshToken = nil;
    for (UIViewFloatAnimatableProperty *p in props) [p invalidate];
    CG27NativeClearMesh(container, nil);
    CG27NativeClearMesh(accessory, nil);
    CG27GenieDriver *keep = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ (void)keep; });
}

- (void)finish {
    [self stop];
    [gCG27Genies removeObjectIdenticalTo:self];
    if (gCG27Genie == self) gCG27Genie = gCG27Genies.lastObject;
}

@end

static void CG27ClearCornerResetAnimations(UIView *root);
static void CG27StartGenie(id modifier, BOOL opening, CGRect icon, id appLayout, double response, double zeta) {
    CGRect window = UIScreen.mainScreen.bounds;
    double W = window.size.width, H = window.size.height;
    double cx = CGRectGetMidX(icon), cy = CGRectGetMidY(icon), iw = icon.size.width;
    double genieScale = CG27GenieScaleForTarget(modifier, appLayout, icon);
    NSNumber *begin = objc_getAssociatedObject(modifier, kCG27GlassBeginKey);
    double glassBegin = [begin isKindOfClass:NSNumber.class] ? begin.doubleValue : CACurrentMediaTime();
    CG27GenieDriver *genie = nil;
    for (CG27GenieDriver *g in gCG27Genies)
        if (g.appLayout && [g.appLayout isEqual:appLayout]) { genie = g; break; }
    if (CG27NativeGenieEnabled()) {
        double drag = UIAnimationDragCoefficient();
        double nativeResponse = response / (isfinite(drag) && drag > 0 ? drag : 1);
        UIView *now = [CG27SwitcherVC() _itemContainerForAppLayoutIfExists:appLayout];
        CG27ClearCornerResetAnimations(now);
        CG27ClearCornerResetAnimations(genie.accessory ?: CG27FindAccessory(now));
        BOOL reuse = genie && genie.native && genie.link && (!genie.container || !now || genie.container == now);
        if (!reuse) {
            [genie finish];
            genie = [CG27GenieDriver new];
            genie.native = YES;
            genie.appLayout = appLayout;
            if (!gCG27Genies) gCG27Genies = [NSMutableArray array];
            [gCG27Genies addObject:genie];
        }
        genie.owner = modifier;
        genie.icon = icon;
        genie.genieScale = genieScale;
        genie.response = nativeResponse;
        genie.zeta = zeta;
        genie.intensity = CG27Intensity();
        genie.iconWidth = iw;
        if (opening) [genie restoreMovingGrabbers];
        genie.opening = opening;
        genie.glassBeginTime = glassBegin;
        genie.shadeStartTime = 0;
        genie.sawLayout = YES;
        gCG27Genie = genie;
        if (reuse) {
            genie.retargeted = YES;
            genie.startTime = genie.lastTime = CACurrentMediaTime();
            [genie nativeLoadEngine:genie.nativeActive];
            return;
        }
        [genie nativeSetUpWithContainer:now targetActive:!opening];
        [genie start];
        return;
    }
    UIView *current = genie.container ? [CG27SwitcherVC() _itemContainerForAppLayoutIfExists:appLayout] : nil;
    if (genie && genie.appLayout && [genie.appLayout isEqual:appLayout] && genie.link &&
        !G27GenieSettled(&genie->_engine) && (!genie.container || genie.container == current)) {
        genie.genieScale = genieScale;
        G27GenieRetargetWithScale(&genie->_engine, !opening, cx, cy, iw, W, H, response, zeta, genieScale);
        genie.owner = modifier;
        genie.startTime = CACurrentMediaTime();
        genie.lastTime = genie.startTime;
        genie.retargeted = YES;
        if (opening) [genie restoreMovingGrabbers];
        genie.opening = opening;
        genie.glassBeginTime = glassBegin;
        genie.shadeStartTime = 0;
        genie.intensity = CG27Intensity();
        genie.sawLayout = NO;
        gCG27Genie = genie;
        return;
    }
    [genie finish];
    genie = [CG27GenieDriver new];
    genie.owner = modifier;
    genie.appLayout = appLayout;
    genie.intensity = CG27Intensity();
    genie.genieScale = genieScale;
    G27GenieStartWithScale(&genie->_engine, !opening, cx, cy, iw, W, H, response, zeta, genieScale);
    genie.iconWidth = iw;
    if (opening) [genie restoreMovingGrabbers];
    genie.opening = opening;
    genie.glassBeginTime = glassBegin;
    if (!gCG27Genies) gCG27Genies = [NSMutableArray array];
    [gCG27Genies addObject:genie];
    gCG27Genie = genie;
    [genie start];
}

@interface UIView (CG27SBAnimate)
+ (void)sb_animateWithSettings:(id)settings mode:(NSInteger)mode animations:(void (^)(void))animations completion:(id)completion;
@end
@interface NSObject (CG27ItemContainer)
- (void)setContentCornerRadii:(CG27CornerRadii)radii;
- (void)setCornerRadius:(double)radius;
- (NSArray *)appLayouts;
- (id)animationAttributesForLayoutElement:(id)element;
- (id)cornerRadiusSettings;
- (id)layoutSettings;
@end

static void CG27ClearCornerResetAnimations(UIView *root) {
    if (!root) return;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        [v.layer removeAnimationForKey:@"cg27.cornerReset"];
        [stack addObjectsFromArray:v.subviews];
    }
}

static void CG27ResetCornerLayers(UIView *root, double radius, SBFFluidBehaviorSettings *settings) {
    if (!root) return;
    double W = UIScreen.mainScreen.bounds.size.width;
    double response = settings.response * UIAnimationDragCoefficient();
    if (!isfinite(response) || response <= 0) return;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass(v.class) containsString:@"Badge"]) continue;
        CALayer *layer = v.layer;
        if (layer.cornerRadius > 0 && v.bounds.size.width > 1) {
            double target = radius * v.bounds.size.width / W;
            double current = (layer.presentationLayer ?: layer).cornerRadius;
            [v stopSettingPresentationValueForKey:@"cornerRadius"];
            [layer removeAnimationForKey:@"cornerRadius"];
            layer.cornerRadius = target;
            CASpringAnimation *animation = [CASpringAnimation animationWithKeyPath:@"cornerRadius"];
            animation.mass = 1;
            animation.stiffness = pow(2 * M_PI / response, 2);
            animation.damping = 4 * M_PI * settings.dampingRatio / response;
            animation.fromValue = @(current); animation.toValue = @(target);
            animation.duration = animation.settlingDuration;
            [layer addAnimation:animation forKey:@"cg27.cornerReset"];
        }
        [stack addObjectsFromArray:v.subviews];
    }
    [CATransaction commit];
}

__attribute__((unused)) static BOOL CG27AnimateCornerReset(id modifier) {
    if (![modifier respondsToSelector:@selector(appLayouts)] || ![modifier respondsToSelector:@selector(_isIndexZoomAppLayout:)] ||
        ![UIView respondsToSelector:@selector(sb_animateWithSettings:mode:animations:completion:)])
        return NO;
    NSArray *layouts = [modifier appLayouts];
    if (![layouts isKindOfClass:NSArray.class]) return NO;
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < layouts.count; i++)
        if ([(SBFullScreenToHomeIconZoomSwitcherModifier *)modifier _isIndexZoomAppLayout:i]) { index = i; break; }
    if (index == NSNotFound) return NO;
    id appLayout = layouts[index];
    UIView *container = [CG27SwitcherVC() _itemContainerForAppLayoutIfExists:appLayout];
    if (!container || ![container respondsToSelector:@selector(setContentCornerRadii:)]) return NO;
    CG27CornerRadii radii = [(SBFullScreenToHomeIconZoomSwitcherModifier *)modifier cornerRadiiForIndex:index];
    if (!isfinite(radii.topLeft) || !isfinite(radii.bottomLeft) || !isfinite(radii.bottomRight) || !isfinite(radii.topRight)) return NO;
    id attributes = [modifier respondsToSelector:@selector(animationAttributesForLayoutElement:)]
        ? [modifier animationAttributesForLayoutElement:appLayout] : nil;
    id settings = CG27UIntIvar(modifier, "_direction") == 1 ? CG27GestureLayoutSettings(appLayout) : nil;
    if (!settings && [attributes respondsToSelector:@selector(cornerRadiusSettings)]) settings = [attributes cornerRadiusSettings];
    if (!settings && [attributes respondsToSelector:@selector(layoutSettings)]) settings = [attributes layoutSettings];
    if (![settings isKindOfClass:%c(SBFFluidBehaviorSettings)]) return NO;
    NSMutableArray<UIView *> *accessories = [NSMutableArray array];
    static Class overlayClass, underlayClass;
    if (!overlayClass) overlayClass = NSClassFromString(@"SBFluidSwitcherSpaceOverlayAccessoryView");
    if (!underlayClass) underlayClass = NSClassFromString(@"SBFluidSwitcherSpaceUnderlayAccessoryView");
    for (UIView *v in container.superview.subviews)
        if (((overlayClass && [v isKindOfClass:overlayClass]) || (underlayClass && [v isKindOfClass:underlayClass])) &&
            !v.hidden && CG27SameFrame(v.layer, container.layer) && [v respondsToSelector:@selector(setCornerRadius:)])
            [accessories addObject:v];
    [UIView sb_animateWithSettings:settings mode:3 animations:^{
        [container setContentCornerRadii:radii];
        for (UIView *v in accessories) [(id)v setCornerRadius:radii.topLeft];
    } completion:nil];
    CG27ResetCornerLayers(container, radii.topLeft, settings);
    for (UIView *v in accessories) CG27ResetCornerLayers(v, radii.topLeft, settings);
    return YES;
}

%hook SBIconBadgeView
- (void)setAccessoryBrightness:(CGFloat)brightness {
    %orig(CG27AppEnabled() ? 1.0 : brightness);
}
%end

%hook SBFullScreenToHomeIconZoomSwitcherModifier

- (id)layoutSettingsForTargetCenter:(CGPoint)center {
    CG27EnsureIOS27Settings(self);
    id settings = %orig;
    if (!settings || !CG27AppEnabled()) return settings;
    NSUInteger direction = CG27UIntIvar(self, "_direction");
    if (direction > 1) return settings;
    double slow = CG27SlowFactor(), closeScale = direction == 0 ? 1.0 : CG27CloseScale();
    if (direction != 0 && slow == 1.0 && closeScale == 1.0) return settings;
    SBFFluidBehaviorSettings *tuned = [settings copy];
    if (@available(iOS 15.0, *))
        if ([settings respondsToSelector:@selector(frameRateRange)] && [settings respondsToSelector:@selector(highFrameRateReason)] &&
            [tuned respondsToSelector:@selector(setFrameRateRange:highFrameRateReason:)])
            [tuned setFrameRateRange:[settings frameRateRange] highFrameRateReason:[settings highFrameRateReason]];
    if (direction == 0) {
        tuned.dampingRatio = kOpenDampingRatio;
        tuned.response = CG27OpenResponse() * slow;
        if ([tuned respondsToSelector:@selector(setRetargetImpulse:)]) tuned.retargetImpulse = 0;
    } else {
        tuned.response = tuned.response * slow * closeScale;
    }
    return tuned;
}

- (id)transitionWillBegin {
    objc_setAssociatedObject(self, kCG27StartedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kCG27CornerResetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kCG27GlassBeginKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return %orig;
}

- (id)handleTimerEvent:(SBTimerSwitcherModifierEvent *)event {
    id response = %orig;
    if (![event.reason isEqualToString:kCG27CornerResetReason]) return response;
    if (!CG27AppEnabled() || CG27UIntIvar(self, "_transitionPhase") != kPhaseWillUpdate) return response;
    objc_setAssociatedObject(self, kCG27CornerResetKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (CG27AnimateCornerReset(self)) return response;
    SBUpdateLayoutSwitcherEventResponse *update = [[%c(SBUpdateLayoutSwitcherEventResponse) alloc] initWithOptions:4 updateMode:3];
    return [%c(SBSwitcherModifierEventResponse) responseByAppendingResponse:update toResponse:response];
}

- (CG27CornerRadii)cornerRadiiForIndex:(NSUInteger)index {
    CG27CornerRadii radii = %orig;
    if (!CG27AppEnabled() || !CG27DropletEnabled() || ![self _isIndexZoomAppLayout:index]) return radii;
    if (CG27IsWidgetTarget(self)) return radii;
    if (CG27UIntIvar(self, "_transitionPhase") != kPhaseWillUpdate) return radii;
    if (objc_getAssociatedObject(self, kCG27CornerResetKey)) return radii;
    NSNumber *started = objc_getAssociatedObject(self, kCG27StartedKey);
    double delay = (CG27UIntIvar(self, "_direction") == 1 ? kCloseCornerResetDelay : kOpenCornerResetDelay) * CG27TimeScale();
    if ([started isKindOfClass:NSNumber.class] && started.doubleValue > 1 && CACurrentMediaTime() - started.doubleValue > delay + 0.05)
        return radii;
    CGRect frame = [self frameForIndex:index];
    double r = MIN(CGRectGetWidth(frame), CGRectGetHeight(frame)) * 0.5;
    if (!isfinite(r) || r <= 0) return radii;
    return (CG27CornerRadii){r, r, r, r};
}

%end

%hook SBTransitionSwitcherModifier

- (id)transitionWillUpdate {
    id response = %orig;
    if (!CG27AppEnabled() || ![self isKindOfClass:%c(SBFullScreenToHomeIconZoomSwitcherModifier)]) return response;
    NSUInteger direction = CG27UIntIvar(self, "_direction");
    if (direction > 1 || objc_getAssociatedObject(self, kCG27StartedKey)) return response;
    objc_setAssociatedObject(self, kCG27StartedKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kCG27CornerResetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    double delay = (direction == 1 ? kCloseCornerResetDelay : kOpenCornerResetDelay) * CG27TimeScale();
    __weak id weakSelf = self;
    SBTimerEventSwitcherEventResponse *timer = [[%c(SBTimerEventSwitcherEventResponse) alloc]
        initWithDelay:delay validator:^BOOL {
            id owner = weakSelf;
            return owner && CG27AppEnabled() && CG27UIntIvar(owner, "_transitionPhase") == kPhaseWillUpdate;
        } reason:kCG27CornerResetReason];
    response = [%c(SBSwitcherModifierEventResponse) responseByAppendingResponse:timer toResponse:response];

    if (CG27GenieEnabled()) {
        Ivar iconIvar = class_getInstanceVariable(object_getClass(self), "_homeScreenIconFrame");
        Ivar layoutIvar = class_getInstanceVariable(object_getClass(self), "_appLayout");
        NSUInteger iconSize = 0;
        if (iconIvar) NSGetSizeAndAlignment(ivar_getTypeEncoding(iconIvar), &iconSize, NULL);
        if (iconIvar && layoutIvar && iconSize == sizeof(CGRect) &&
            !strncmp(ivar_getTypeEncoding(iconIvar), "{CGRect=", 8) &&
            ivar_getTypeEncoding(layoutIvar)[0] == '@') {
            CGRect icon = *(CGRect *)((uint8_t *)(__bridge void *)self + ivar_getOffset(iconIvar));
            CGRect window = UIScreen.mainScreen.bounds;
            if (!CGRectIsEmpty(icon) && !CGRectIsInfinite(icon) &&
                isfinite(icon.origin.x) && isfinite(icon.origin.y) &&
                isfinite(icon.size.width) && isfinite(icon.size.height) &&
                window.size.height > window.size.width) {
                BOOL opening = direction == 0;
                double spring = opening ? CG27OpenResponse() : kCloseResponse * CG27CloseScale(), zeta = 1.0;
                id appLayout = object_getIvar(self, layoutIvar);
                SBFFluidBehaviorSettings *settings = opening ? nil : CG27GestureLayoutSettings(appLayout);
                if (!settings)
                    settings = [(SBFullScreenToHomeIconZoomSwitcherModifier *)self
                        layoutSettingsForTargetCenter:CGPointMake(CGRectGetMidX(icon), CGRectGetMidY(icon))];
                if ([settings respondsToSelector:@selector(response)] && settings.response > 0.05 && settings.response < 5) {
                    spring = settings.response;
                    if (settings.dampingRatio > 0.3 && settings.dampingRatio < 3) zeta = settings.dampingRatio;
                }
                gCG27FrameRateReason = [settings respondsToSelector:@selector(highFrameRateReason)]
                    ? [settings highFrameRateReason] : kCG27DefaultFrameRateReason;
                double drag = UIAnimationDragCoefficient();
                if (!isfinite(drag) || drag <= 0) drag = 1;
                spring *= drag;
                CG27StartGenie(self, opening, icon, appLayout, spring, zeta);
            }
        }
    }
    return response;
}

%end

@interface SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier : NSObject
- (id)_layoutSettings;
- (double)_normalizedHomeScreenIconZoomPercentBetweenTopAndBottom;
@end
@interface SBMutableSwitcherAnimationAttributes : NSObject
- (id)layoutSettings;
- (void)setCornerRadiusSettings:(id)settings;
- (void)setCornerRadiusUpdateMode:(NSInteger)mode;
@end

static id CG27WithCornerSpring(id modifier, id element, id attributes) {
    if (!attributes || !CG27AppEnabled() || !CG27GenieEnabled() || ![element isKindOfClass:%c(SBAppLayout)]) return attributes;
    if (CG27IsWidgetTarget(modifier) &&
        ([modifier isKindOfClass:%c(SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier)] ||
         CG27UIntIvar(modifier, "_direction") == 1)) return attributes;
    Ivar iv = class_getInstanceVariable(object_getClass(modifier), "_appLayout");
    if (!iv || ivar_getTypeEncoding(iv)[0] != '@' || ![element isEqual:object_getIvar(modifier, iv)]) return attributes;
    if (![attributes respondsToSelector:@selector(layoutSettings)] || ![attributes respondsToSelector:@selector(setCornerRadiusSettings:)])
        return attributes;
    id layout = [attributes layoutSettings];
    if (!layout) return attributes;
    id copy = [attributes respondsToSelector:@selector(mutableCopyWithZone:)] ? [attributes mutableCopy] : attributes;
    if (![copy respondsToSelector:@selector(setCornerRadiusSettings:)]) return attributes;
    [(SBMutableSwitcherAnimationAttributes *)copy setCornerRadiusSettings:layout];
    if ([copy respondsToSelector:@selector(setCornerRadiusUpdateMode:)]) [(SBMutableSwitcherAnimationAttributes *)copy setCornerRadiusUpdateMode:3];
    return copy;
}

static __weak SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier *gCG27GestureZoom;

static id CG27GestureLayoutSettings(id appLayout) {
    SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier *gesture = gCG27GestureZoom;
    if (!gesture || !appLayout || ![gesture respondsToSelector:@selector(_layoutSettings)]) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(gesture), "_appLayout");
    if (!iv || ![object_getIvar(gesture, iv) isEqual:appLayout]) return nil;
    id settings = [gesture _layoutSettings];
    return [settings isKindOfClass:%c(SBFFluidBehaviorSettings)] ? settings : nil;
}

%hook SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier
- (id)initWithAppLayout:(id)appLayout gestureEdge:(NSUInteger)edge liftOffVelocity:(CGPoint)velocity {
    id result = %orig;
    if (result) gCG27GestureZoom = result;
    return result;
}

- (id)animationAttributesForLayoutElement:(id)element {
    id attributes = %orig;
    return CG27WithCornerSpring(self, element, attributes);
}
%end

%hook SBFullScreenToHomeIconZoomSwitcherModifier
- (id)animationAttributesForLayoutElement:(id)element {
    id attributes = %orig;
    if (CG27UIntIvar(self, "_direction") > 1) return attributes;
    return CG27WithCornerSpring(self, element, attributes);
}
%end

@interface SBFluidSwitcherAnimationSettings : NSObject
@end

static NSMutableDictionary<NSString *, NSNumber *> *gCG27StockSettings;

static void CG27SetNumber(id object, NSString *property, NSString *stockKey, double value) {
    if (!gCG27StockSettings) gCG27StockSettings = [NSMutableDictionary dictionary];
    @try {
        if (!gCG27StockSettings[stockKey]) {
            NSNumber *stock = [object valueForKey:property];
            if (![stock isKindOfClass:NSNumber.class]) return;
            gCG27StockSettings[stockKey] = stock;
        }
        [object setValue:@(value) forKey:property];
    } @catch (NSException *e) {}
}

static void CG27SetSpring(id root, NSString *key, double ratio, double response, double impulse) {
    SBFFluidBehaviorSettings *spring = nil;
    @try { spring = [root valueForKey:key]; } @catch (NSException *e) { return; }
    if (![spring isKindOfClass:%c(SBFFluidBehaviorSettings)]) return;
    if (ratio > 0) CG27SetNumber(spring, @"dampingRatio", [key stringByAppendingString:@".dampingRatio"], ratio);
    if (response > 0) CG27SetNumber(spring, @"response", [key stringByAppendingString:@".response"], response);
    if (impulse >= 0) CG27SetNumber(spring, @"retargetImpulse", [key stringByAppendingString:@".retargetImpulse"], impulse);
}

static void CG27SetValue(id root, NSString *key, double value) {
    CG27SetNumber(root, key, key, value);
}

static void CG27RestoreStockSettings(id s) {
    if (!s) return;
    [gCG27StockSettings enumerateKeysAndObjectsUsingBlock:^(NSString *stockKey, NSNumber *value, __unused BOOL *stop) {
        NSRange dot = [stockKey rangeOfString:@"."];
        @try {
            id object = dot.location == NSNotFound ? s : [s valueForKey:[stockKey substringToIndex:dot.location]];
            NSString *property = dot.location == NSNotFound ? stockKey : [stockKey substringFromIndex:NSMaxRange(dot)];
            [object setValue:value forKey:property];
        } @catch (NSException *e) {}
    }];
}

static const double kCG27ZoomDownResponseMultiplier = 0.8;

static NSHashTable *gCG27AppliedSettings;

static void CG27ApplyIOS27Settings(id s) {
    if (!s || !CG27AppEnabled()) return;
    if (!gCG27AppliedSettings) gCG27AppliedSettings = [NSHashTable weakObjectsHashTable];
    [gCG27AppliedSettings addObject:s];
    for (NSString *row in @[@"TopRow", @"BottomRow"])
        for (NSString *kind in @[@"Layout", @"Position", @"Scale"])
            CG27SetSpring(s, [NSString stringWithFormat:@"homeGesture%@ZoomDown%@Settings", row, kind], -1, -1, 0);
    CG27SetSpring(s, @"homeGestureTopRowZoomDownPositionSettings", 0.8, 0.45, 0);
    CG27SetSpring(s, @"homeGestureTopRowZoomDownScaleSettings", 0.84, 0.55, 0);
    CG27SetSpring(s, @"homeGestureSmallWidgetZoomDownLayoutSettings", 1.1, 0.425, 0.016);
    CG27SetSpring(s, @"homeGestureSmallWidgetZoomDownPositionSettings", 0.88, 0.45, 0.02);
    CG27SetSpring(s, @"homeGestureSmallWidgetZoomDownScaleSettings", 0.96, 0.54, 0.018);
    CG27SetSpring(s, @"homeGestureMediumWidgetZoomDownLayoutSettings", 0.96, 0.32, 0.016);
    CG27SetSpring(s, @"homeGestureMediumWidgetZoomDownPositionSettings", 0.88, 0.45, 0.02);
    CG27SetSpring(s, @"homeGestureMediumWidgetZoomDownScaleSettings", 0.96, 0.54, 0);
    CG27SetSpring(s, @"homeGestureLargeWidgetZoomDownLayoutSettings", 0.96, 0.4, 0.016);
    CG27SetSpring(s, @"homeGestureLargeWidgetZoomDownPositionSettings", 0.88, 0.45, 0);
    CG27SetSpring(s, @"homeGestureLargeWidgetZoomDownScaleSettings", 0.96, 0.54, 0);
    CG27SetSpring(s, @"homeGestureCenterRowZoomUpSettings", -1, -1, 0);
    CG27SetSpring(s, @"homeGestureEdgeRowZoomUpSettings", -1, -1, 0);
    CG27SetSpring(s, @"homeScreenOpacitySettings", 1.0, 0.23, -1);
    if (CG27BoolPref(CFSTR("NativeWallpaperZoom"), NO)) {
        NSNumber *stock = gCG27StockSettings[@"wallpaperScaleInApplication"];
        if (stock) @try { [s setValue:stock forKey:@"wallpaperScaleInApplication"]; } @catch (NSException *e) {}
    } else {
        CG27SetValue(s, @"wallpaperScaleInApplication", 1.0);
    }
    CG27SetValue(s, @"crossblurDosidoSmallScale", 0.55);
    CG27SetValue(s, @"siriSwipeDismissClientAnimationsDelay", 0.0);
}

%hook SBFluidSwitcherAnimationSettings
- (void)setDefaultValues {
    %orig;
    CG27ApplyIOS27Settings(self);
}
%end

@interface NSObject (CG27SwitcherSettings)
- (id)switcherSettings;
@end

static void CG27EnsureIOS27Settings(id modifier) {
    if (!CG27AppEnabled() || ![modifier respondsToSelector:@selector(switcherSettings)]) return;
    id animation = nil;
    SBFFluidBehaviorSettings *probe = nil;
    @try {
        animation = [[modifier switcherSettings] valueForKey:@"animationSettings"];
        if ([animation isKindOfClass:%c(SBFluidSwitcherAnimationSettings)])
            probe = [animation valueForKey:@"homeGestureTopRowZoomDownPositionSettings"];
    } @catch (NSException *e) { return; }
    if (![probe isKindOfClass:%c(SBFFluidBehaviorSettings)]) return;
    double ratio = 0.8;
    BOOL known = [gCG27AppliedSettings containsObject:animation];
    if (known && fabs(probe.dampingRatio - ratio) < 0.001 && probe.retargetImpulse == 0) return;
    CG27ApplyIOS27Settings(animation);
}

%hook SBFullScreenToHomeCenterZoomDownSwitcherModifier
- (id)_layoutSettings {
    CG27EnsureIOS27Settings(self);
    return %orig;
}
%end

enum { kCG27ZoomSpringOther = 0, kCG27ZoomSpringPosition, kCG27ZoomSpringScale };
static int gCG27ZoomSpringKind;

static id CG27SmallWidgetGestureSpring(id modifier, id original, int kind) {
    if (!CG27AppEnabled() || UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone ||
        CG27UIntIvar(modifier, "_iconGridSizeClass") != 1 ||
        ![original isKindOfClass:%c(SBFFluidBehaviorSettings)] ||
        ![modifier respondsToSelector:@selector(_normalizedHomeScreenIconZoomPercentBetweenTopAndBottom)]) return original;
    double p = [(SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier *)modifier
        _normalizedHomeScreenIconZoomPercentBetweenTopAndBottom];
    if (!isfinite(p)) return original;
    p = G27Clamp(p, 0, 1);
    CGPoint velocity = CGPointZero;
    Ivar iv = class_getInstanceVariable(object_getClass(modifier), "_liftOffVelocity");
    NSUInteger size = 0;
    if (iv) NSGetSizeAndAlignment(ivar_getTypeEncoding(iv), &size, NULL);
    if (iv && size == sizeof(CGPoint))
        velocity = *(CGPoint *)((uint8_t *)(__bridge void *)modifier + ivar_getOffset(iv));
    SBFFluidBehaviorSettings *spring = [original copy];
    double factor = 0.75 * CG27CloseScale();
    if (kind == kCG27ZoomSpringOther) {
        factor *= 1 - 0.3 * G27Clamp((-velocity.y - 3000) / 2000, 0, 1);
        spring.dampingRatio = 1.1;
        spring.response = (0.425 - 0.05 * p) * factor;
    } else if (kind == kCG27ZoomSpringPosition) {
        factor *= 1 + 0.2 * G27Clamp((fabs(velocity.x) - 1000) / 3000, 0, 1);
        spring.dampingRatio = 0.8 + 0.06 * p;
        spring.response = (0.45 + 0.1 * p) * factor;
    } else {
        spring.dampingRatio = 0.84;
        spring.response = 0.55 * factor;
    }
    spring.retargetImpulse = 0;
    if (kind != kCG27ZoomSpringOther && [spring respondsToSelector:@selector(setFrameRateRange:highFrameRateReason:)])
        [spring setFrameRateRange:CAFrameRateRangeMake(80, 120, 120) highFrameRateReason:0x110003];
    return spring;
}

%hook SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier
- (id)_layoutSettings {
    CG27EnsureIOS27Settings(self);
    id settings = %orig;
    return CG27SmallWidgetGestureSpring(self, settings, kCG27ZoomSpringOther);
}

- (id)_positionSettings {
    CG27EnsureIOS27Settings(self);
    gCG27ZoomSpringKind = kCG27ZoomSpringPosition;
    id settings = %orig;
    gCG27ZoomSpringKind = kCG27ZoomSpringOther;
    return CG27SmallWidgetGestureSpring(self, settings, kCG27ZoomSpringPosition);
}

- (id)_scaleSettings {
    CG27EnsureIOS27Settings(self);
    gCG27ZoomSpringKind = kCG27ZoomSpringScale;
    id settings = %orig;
    gCG27ZoomSpringKind = kCG27ZoomSpringOther;
    return CG27SmallWidgetGestureSpring(self, settings, kCG27ZoomSpringScale);
}

- (id)_settingsByInterpolatingBetween:(id)a and:(id)b progress:(double)progress {
    CG27EnsureIOS27Settings(self);
    int kind = gCG27ZoomSpringKind;
    SBFFluidBehaviorSettings *settings = %orig;
    if (!CG27AppEnabled() || UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone ||
        ![settings isKindOfClass:%c(SBFFluidBehaviorSettings)] || settings.response <= 0.05)
        return settings;
    if (kind != kCG27ZoomSpringOther && isfinite(progress)) {
        double p = fmin(fmax(progress, 0), 1);
        BOOL position = kind == kCG27ZoomSpringPosition;
        double ratioTop = position ? 0.8 : 0.84, ratioBottom = position ? 0.86 : 0.84;
        double responseTop = position ? 0.45 : 0.55, responseBottom = 0.55;
        double ratio = ratioTop + (ratioBottom - ratioTop) * p, response = responseTop + (responseBottom - responseTop) * p;
        settings.dampingRatio = ratio;
        settings.response = response;
        settings.retargetImpulse = 0;
    }
    settings.response = settings.response * kCG27ZoomDownResponseMultiplier * CG27CloseScale();
    return settings;
}
%end

@interface SBRootFolderController : NSObject
- (UIView *)currentIconListView;
- (UIView *)dockListView;
- (UIView *)view;
- (id)beginModifyingDockOffscreenFractionForReason:(NSString *)reason;
@end
@interface SBCG27DockOffscreenModifier : NSObject
- (void)setDockOffscreenFraction:(double)fraction;
- (void)invalidate;
@end
@interface UIView (CG27PrivateSpring)
+ (void)_animateUsingSpringWithTension:(double)tension friction:(double)friction interactive:(BOOL)interactive
                            animations:(void (^)(void))animations completion:(void (^)(BOOL))completion;
@end
@interface SBHIconManager : NSObject
- (SBRootFolderController *)rootFolderController;
@end
@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
- (SBHIconManager *)iconManager;
@end
@interface SBWallpaperController : NSObject
+ (instancetype)sharedInstance;
@end
@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

static const double kCG27FlyCameraDistance = 5082.15;
static const double kCG27FlyFarZ = 10000.0;
static const double kCG27FlyMaxDistance = 366.0;
static const double kCG27FlyZResponse = 0.42, kCG27FlyZCurve = 1.4;
static const double kCG27FlyZDampingMax = 0.82, kCG27FlyZDampingSlope = -0.22 / 7, kCG27FlyZDampingFrom = 3;
static const double kCG27FlySpreadResponse = 0.36;
static const double kCG27FlyBlurIn = 6.0, kCG27FlyBlurOut = 10.0;
static const double kCG27FlyDockResponse = 0.547826087, kCG27FlyDockDamping = 0.74, kCG27FlyDockOffscreen = 4.0;
static NSString *const kCG27FlyInKey = @"iOS27AnimsRebornFlyIn";
static NSString *const kCG27FlyBlurName = @"CG27FlyBlur";

static BOOL gCG27FlyHidden;
static BOOL gCG27FlyOutArmed;
static BOOL gCG27SheetSettledShown = YES;
static NSInteger gCG27FlyGeneration;

static double CG27FlyStartScale(void) {
    return 1.7;
}

static double CG27FlySpreadResponse(void) {
    return kCG27FlySpreadResponse;
}

static void CG27FlyRemoveBlur(CALayer *layer) {
    NSMutableArray *filters = [layer.filters mutableCopy];
    NSIndexSet *ours = [filters indexesOfObjectsPassingTest:^BOOL(id f, __unused NSUInteger idx, __unused BOOL *stop) {
        return [[f valueForKey:@"name"] isEqual:kCG27FlyBlurName];
    }];
    if (!ours.count) return;
    [filters removeObjectsAtIndexes:ours];
    layer.filters = filters.count ? filters : nil;
}

static void CG27FlyAddBlur(CALayer *layer, CAFilter *blur) {
    CG27FlyRemoveBlur(layer);
    layer.filters = [(layer.filters ?: @[]) arrayByAddingObject:blur];
}

static double CG27FlyCurrentBlur(CALayer *layer) {
    for (id f in ((CALayer *)layer.presentationLayer ?: layer).filters)
        if ([[f valueForKey:@"name"] isEqual:kCG27FlyBlurName]) return [[f valueForKey:@"inputRadius"] doubleValue];
    return 0;
}

static BOOL CG27FlyInEnabled(void) {
    if (!CG27Enabled()) return NO;
    CFPropertyListRef v = CG27CopyPref(CFSTR("IconFlyIn"));
    BOOL on = !v || (CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue((CFBooleanRef)v) : YES);
    if (v) CFRelease(v);
    return on;
}

static SBRootFolderController *CG27FlyRoot(void) {
    SBIconController *ic = [%c(SBIconController) sharedInstance];
    return [ic respondsToSelector:@selector(iconManager)] ? [[ic iconManager] rootFolderController] : nil;
}

static UIView *CG27FlyList(void) {
    SBRootFolderController *root = CG27FlyRoot();
    UIView *list = [root respondsToSelector:@selector(currentIconListView)] ? [root currentIconListView] : nil;
    return list.window ? list : nil;
}

static UIView *CG27FlyDock(void) {
    SBRootFolderController *root = CG27FlyRoot();
    UIView *dock = [root respondsToSelector:@selector(dockListView)] ? [root dockListView] : nil;
    for (UIView *v = dock; v; v = v.superview)
        if ([v isKindOfClass:%c(SBDockView)]) return v.window ? v : nil;
    return dock.window ? dock : nil;
}

static BOOL CG27FlyHomeVisible(void) {
    UIApplication *app = UIApplication.sharedApplication;
    SEL front = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    if (![app respondsToSelector:front]) return NO;
    return ((id (*)(id, SEL))objc_msgSend)(app, front) == nil;
}

static id gCG27FlyDockModifier;

static void CG27FlyDockLayout(SBRootFolderController *root) {
    SEL lay = NSSelectorFromString(@"layoutIfNeededForDockOffscreenFractionChanged");
    if ([gCG27FlyDockModifier respondsToSelector:lay]) ((void (*)(id, SEL))objc_msgSend)(gCG27FlyDockModifier, lay);
    else if ([root respondsToSelector:lay]) ((void (*)(id, SEL))objc_msgSend)(root, lay);
    else [root.view layoutIfNeeded];
}

static BOOL CG27FlyDockOffscreen(BOOL offscreen) {
    SBRootFolderController *root = CG27FlyRoot();
    if (offscreen) {
        if (!gCG27FlyDockModifier && [root respondsToSelector:@selector(beginModifyingDockOffscreenFractionForReason:)])
            gCG27FlyDockModifier = [root beginModifyingDockOffscreenFractionForReason:@"iOS27AnimsRebornFlyIn"];
        if (![gCG27FlyDockModifier respondsToSelector:@selector(setDockOffscreenFraction:)]) { gCG27FlyDockModifier = nil; return NO; }
        [UIView performWithoutAnimation:^{
            [gCG27FlyDockModifier setDockOffscreenFraction:kCG27FlyDockOffscreen];
            CG27FlyDockLayout(root);
        }];
    } else if (gCG27FlyDockModifier) {
        [UIView performWithoutAnimation:^{
            [gCG27FlyDockModifier setDockOffscreenFraction:0];
            CG27FlyDockLayout(root);
        }];
        [gCG27FlyDockModifier invalidate];
        gCG27FlyDockModifier = nil;
    }
    return YES;
}

static CASpringAnimation *CG27FlySpring(NSString *keyPath, id from, id to, double response, double damping, double velocity) {
    CASpringAnimation *a = [CASpringAnimation animationWithKeyPath:keyPath];
    double w = 2 * M_PI / response;
    a.mass = 1;
    a.stiffness = w * w;
    a.damping = 2 * damping * w;
    a.initialVelocity = velocity;
    a.fromValue = from;
    a.toValue = to;
    a.duration = a.settlingDuration;
    a.fillMode = kCAFillModeBoth;
    a.removedOnCompletion = NO;
    return a;
}

static CAAnimation *CG27FlyAnimationAt(CALayer *layer, double now) {
    CAAnimation *animation = [layer animationForKey:kCG27FlyInKey];
    if (!animation) return nil;
    double elapsed = ([layer convertTime:now fromLayer:nil] - animation.beginTime) * animation.speed + animation.timeOffset;
    if (!isfinite(elapsed) || elapsed >= animation.duration) return nil;
    return animation;
}

static void CG27FlyCollect(UIView *v, int depth, NSMapTable<UIView *, NSNumber *> *ys) {
    if (depth > 7 || v.hidden) return;
    [ys setObject:@([v convertPoint:CGPointZero toView:nil].y) forKey:v];
    for (UIView *c in v.subviews) CG27FlyCollect(c, depth + 1, ys);
}

static CGPoint CG27FlyVelocity(CALayer *layer, CAAnimation *animation, NSString *key, double now);
static BOOL CG27FlyDockSlide(BOOL offscreen, double begin, double *longest) {
    UIView *rootView = CG27FlyRoot().view;
    if (!rootView || (!offscreen && !gCG27FlyDockModifier)) return NO;
    NSMapTable<UIView *, NSNumber *> *before = [NSMapTable strongToStrongObjectsMapTable], *after = [NSMapTable strongToStrongObjectsMapTable];
    CG27FlyCollect(rootView, 0, before);
    NSMapTable<UIView *, NSValue *> *motion = [NSMapTable strongToStrongObjectsMapTable];
    for (UIView *v in before) {
        CAAnimation *old = CG27FlyAnimationAt(v.layer, begin);
        if (![old isKindOfClass:CASpringAnimation.class] || ![((CASpringAnimation *)old).keyPath isEqual:@"position.y"]) continue;
        CALayer *shown = v.layer.presentationLayer ?: v.layer;
        CGPoint state = CGPointMake(shown.position.y - v.layer.position.y, CG27FlyVelocity(v.layer, old, @"position.y", begin).x);
        [motion setObject:[NSValue valueWithCGPoint:state] forKey:v];
    }
    if (!CG27FlyDockOffscreen(offscreen)) return NO;
    CG27FlyCollect(rootView, 0, after);
    for (UIView *v in before) {
        NSNumber *y1 = [after objectForKey:v];
        if (!y1) continue;
        double layoutDelta = [before objectForKey:v].doubleValue - y1.doubleValue;
        CGPoint state = [[motion objectForKey:v] CGPointValue];
        double d = layoutDelta + state.x;
        if (fabs(d) < 0.5) { if ([motion objectForKey:v]) [v.layer removeAnimationForKey:kCG27FlyInKey]; continue; }
        UIView *sup = v.superview;
        NSNumber *s0 = sup ? [before objectForKey:sup] : nil, *s1 = sup ? [after objectForKey:sup] : nil;
        if (s0 && s1 && fabs((s0.doubleValue - s1.doubleValue) - layoutDelta) < 0.5 && ![motion objectForKey:v]) continue;
        CASpringAnimation *slide = CG27FlySpring(@"position.y", @(d), @0, kCG27FlyDockResponse, kCG27FlyDockDamping, -state.y / d);
        slide.additive = YES;
        slide.removedOnCompletion = YES;
        slide.beginTime = begin;
        double drag = UIAnimationDragCoefficient();
        if (isfinite(drag) && drag > 1) slide.speed = (float)(1.0 / drag);
        [v.layer addAnimation:slide forKey:kCG27FlyInKey];
        *longest = fmax(*longest, slide.duration);
    }
    return YES;
}

static NSHashTable<UIView *> *gCG27FlyLists;
static const void *kCG27FlySavedTransformKey = &kCG27FlySavedTransformKey;

static void CG27FlyTouch(UIView *list) {
    if (!list) return;
    if (!gCG27FlyLists) gCG27FlyLists = [NSHashTable weakObjectsHashTable];
    [gCG27FlyLists addObject:list];
    if (!objc_getAssociatedObject(list, kCG27FlySavedTransformKey))
        objc_setAssociatedObject(list, kCG27FlySavedTransformKey, [NSValue valueWithCATransform3D:list.layer.sublayerTransform],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CG27FlyResetList(UIView *list, BOOL keepAnimations) {
    NSValue *saved = objc_getAssociatedObject(list, kCG27FlySavedTransformKey);
    if (saved) list.layer.sublayerTransform = saved.CATransform3DValue;
    objc_setAssociatedObject(list, kCG27FlySavedTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CG27FlyRemoveBlur(list.layer);
    if (!keepAnimations) [list.layer removeAnimationForKey:kCG27FlyInKey];
    for (UIView *iv in list.subviews) {
        if (![iv isKindOfClass:%c(SBIconView)]) continue;
        if (!keepAnimations) [iv.layer removeAnimationForKey:kCG27FlyInKey];
        for (UIView *part in iv.subviews) {
            if (!keepAnimations) [part.layer removeAnimationForKey:kCG27FlyInKey];
            CG27FlyRemoveBlur(part.layer);
        }
    }
}

static void CG27FlyResetOtherLists(UIView *current) {
    for (UIView *list in gCG27FlyLists.allObjects) {
        if (list == current) continue;
        CG27FlyResetList(list, NO);
        list.layer.opacity = 1;
        [gCG27FlyLists removeObject:list];
    }
}

static void CG27FlySetHidden(BOOL hidden) {
    gCG27FlyHidden = hidden;
    ++gCG27FlyGeneration;
    UIView *list = CG27FlyList(), *dock = CG27FlyDock();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CG27FlyResetOtherLists(list);
    if (hidden) {
        [list.layer removeAnimationForKey:kCG27FlyInKey];
        CG27FlyTouch(list);
    } else if (list) {
        CG27FlyResetList(list, NO);
    }
    list.layer.opacity = hidden ? 0 : 1;
    [CATransaction commit];
    [dock.layer removeAnimationForKey:kCG27FlyInKey];
    BOOL moved = CG27FlyDockOffscreen(hidden);
    dock.layer.opacity = (hidden && !moved) ? 0 : 1;
}

static CGPoint CG27FlyVelocity(CALayer *layer, CAAnimation *animation, NSString *key, double now) {
    if (!animation) return CGPointZero;
    NSArray *children = [animation isKindOfClass:CAAnimationGroup.class] ? ((CAAnimationGroup *)animation).animations : @[animation];
    double elapsed = ([layer convertTime:now fromLayer:nil] - animation.beginTime) * animation.speed + animation.timeOffset;
    for (CAAnimation *child in children) {
        if (![child isKindOfClass:CASpringAnimation.class]) continue;
        CASpringAnimation *spring = (id)child;
        if (![spring.keyPath isEqual:key] || elapsed < 0 || elapsed >= spring.duration) continue;
        double x = 0, rate = spring.initialVelocity;
        double w = sqrt(spring.stiffness / spring.mass);
        G27SpringStep(&x, &rate, 1, 2 * M_PI / w, spring.damping / (2 * spring.mass * w), elapsed);
        if ([key isEqual:@"position"]) {
            CGPoint a = [spring.fromValue CGPointValue], b = [spring.toValue CGPointValue];
            return CGPointMake((b.x - a.x) * rate, (b.y - a.y) * rate);
        }
        return CGPointMake(([spring.toValue doubleValue] - [spring.fromValue doubleValue]) * rate, 0);
    }
    return CGPointZero;
}

static CAKeyframeAnimation *CG27FlyVisibility(double from, double to, double velocity, double response,
                                             double damping, double duration) {
    NSMutableArray *values = [NSMutableArray array], *times = [NSMutableArray array];
    const int count = MAX(1, (int)ceil(duration * 120));
    double z = from, zv = velocity, dt = duration / count;
    for (int i = 0; i < count; i++) {
        NSNumber *visible = @(z < kCG27FlyCameraDistance * 0.98 ? 1 : 0);
        if (!values.count || ![values.lastObject isEqual:visible]) {
            [values addObject:visible]; [times addObject:@((double)i / count)];
        }
        G27SpringStep(&z, &zv, to, response, damping, dt);
    }
    [times addObject:@1];
    CAKeyframeAnimation *show = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    show.values = values; show.keyTimes = times; show.calculationMode = kCAAnimationDiscrete; show.duration = duration;
    show.fillMode = kCAFillModeBoth; show.removedOnCompletion = NO;
    return show;
}

static BOOL CG27FlyIconHasBackdrop(UIView *iconView) {
    id icon = [iconView respondsToSelector:@selector(icon)] ? ((id (*)(id, SEL))objc_msgSend)(iconView, @selector(icon)) : nil;
    if (!icon) return NO;
    for (NSString *sel in @[@"isWidgetIcon", @"isFolderIcon", @"isWidgetStackIcon"]) {
        SEL s = NSSelectorFromString(sel);
        if ([icon respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(icon, s)) return YES;
    }
    NSString *name = NSStringFromClass([icon class]);
    return [name containsString:@"Widget"] || [name containsString:@"Folder"];
}

static BOOL CG27FlyIconOverflows(UIView *iconView) {
    CGRect bounds = iconView.bounds;
    NSMutableArray<UIView *> *stack = [iconView.subviews mutableCopy];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v.hidden || v.alpha < 0.01) continue;
        if ([NSStringFromClass(v.class) containsString:@"Badge"]) {
            CGRect r = [v convertRect:v.bounds toView:iconView];
            if (!CGRectContainsRect(CGRectInset(bounds, -0.5, -0.5), r)) return YES;
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return NO;
}

static void CG27FlyRun(BOOL flyIn, double velocity) {
    double drag = UIAnimationDragCoefficient();
    float flySpeed = isfinite(drag) && drag > 1 ? (float)(1.0 / drag) : 1.0f;
    UIView *list = CG27FlyList(), *dock = CG27FlyDock();
    if (!list && !dock) { gCG27FlyHidden = !flyIn; return; }
    NSInteger generation = ++gCG27FlyGeneration;
    gCG27FlyHidden = !flyIn;
    UIWindow *window = (list ?: dock).window;
    CGSize W = window.bounds.size;
    CGPoint screenCenter = CGPointMake(W.width / 2, W.height / 2);
    CGPoint spreadCenterW = CGPointMake(W.width / 2, W.height / 2 - 16);
    double begin = CACurrentMediaTime();
    double v = fmin(fmax(velocity, -10), 10);
    double spreadVelocity = (flyIn ? 2 : 4) * v;
    double spreadResponse = CG27FlySpreadResponse();
    double towardSpread = flyIn ? spreadVelocity : -spreadVelocity;
    double zVelocity = -(W.height * v) / 200;
    double zDamping = fmin(kCG27FlyZDampingMax + (v - kCG27FlyZDampingFrom) * kCG27FlyZDampingSlope, kCG27FlyZDampingMax);
    double zFrom = flyIn ? kCG27FlyFarZ : 0, zTo = flyIn ? 0 : kCG27FlyFarZ;
    double longest = 0;

    id wallpaper = [%c(SBWallpaperController) respondsToSelector:@selector(sharedInstance)] ? [%c(SBWallpaperController) sharedInstance] : nil;
    SEL wsel = NSSelectorFromString(@"updateWallpaperAnimationWithIconFlyInTension:friction:");
    if ([wallpaper respondsToSelector:wsel]) ((void (*)(id, SEL, double, double))objc_msgSend)(wallpaper, wsel, 72.0, 14.4);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CG27FlyResetOtherLists(list);
    if (list) {
        CALayer *L = list.layer;
        BOOL retarget = CG27FlyAnimationAt(L, begin) != nil;
        for (UIView *iv in list.subviews)
            if ([iv isKindOfClass:%c(SBIconView)] && CG27FlyAnimationAt(iv.layer, begin)) { retarget = YES; break; }
        double alphaFrom = retarget ? ((CALayer *)L.presentationLayer ?: L).opacity : 1;
        double blurFrom = CG27FlyCurrentBlur(L);
        for (UIView *iv in list.subviews)
            if ([iv isKindOfClass:%c(SBIconView)])
                for (UIView *part in iv.subviews) blurFrom = fmax(blurFrom, CG27FlyCurrentBlur(part.layer));
        [L removeAnimationForKey:kCG27FlyInKey];
        CG27FlyTouch(list);
        CG27FlyRemoveBlur(L);
        BOOL backdrops = NO;
        for (UIView *iv in list.subviews)
            if ([iv isKindOfClass:%c(SBIconView)] && !iv.hidden && CG27FlyIconHasBackdrop(iv)) { backdrops = YES; break; }
        CGPoint c = [list convertPoint:screenCenter fromView:nil];
        CGPoint anchor = CGPointMake(CGRectGetMidX(list.bounds), CGRectGetMidY(list.bounds));
        CATransform3D P = CATransform3DIdentity;
        P.m34 = -1.0 / kCG27FlyCameraDistance;
        L.sublayerTransform = CATransform3DConcat(CATransform3DConcat(
            CATransform3DMakeTranslation(-(c.x - anchor.x), -(c.y - anchor.y), 0), P),
            CATransform3DMakeTranslation(c.x - anchor.x, c.y - anchor.y, 0));
        L.opacity = flyIn ? 1 : 0;

        NSMutableArray *radii = [NSMutableArray array], *alphas = [NSMutableArray array];
        double q = 0, qv = towardSpread, dt = 1.0 / 120, R = flyIn ? kCG27FlyBlurIn : kCG27FlyBlurOut;
        if (!retarget) blurFrom = flyIn ? R : 0;
        double blurTo = flyIn ? 0 : R, alphaTo = flyIn ? 1 : 0;
        const int n = 150;
        for (int i = 0; i <= n; i++) {
            double qi = i == n ? 1 : G27Clamp(q, 0, 1);
            [radii addObject:@(blurFrom + (blurTo - blurFrom) * qi)];
            [alphas addObject:@(retarget ? alphaFrom + (alphaTo - alphaFrom) * qi : (1 - qi) * (1 - qi))];
            G27SpringStep(&q, &qv, 1, spreadResponse, 1, dt);
        }
        NSMutableArray *anims = [NSMutableArray array];
        CAFilter *blur = [%c(CAFilter) filterWithType:@"gaussianBlur"];
        CAKeyframeAnimation *blurAnim = nil;
        if (blur) {
            [blur setValue:kCG27FlyBlurName forKey:@"name"];
            [blur setValue:@(flyIn ? 0 : R) forKey:@"inputRadius"];
            blurAnim = [CAKeyframeAnimation animationWithKeyPath:@"filters.CG27FlyBlur.inputRadius"];
            blurAnim.values = radii; blurAnim.duration = n * dt;
            if (!backdrops) { CG27FlyAddBlur(L, blur); [anims addObject:blurAnim]; }
        }
        if (!flyIn || retarget) {
            CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            a.values = alphas; a.duration = n * dt;
            [anims addObject:a];
        }
        if (anims.count) {
            CAAnimationGroup *g = [CAAnimationGroup animation];
            g.animations = anims; g.duration = n * dt; g.beginTime = begin; g.fillMode = kCAFillModeBackwards;
            g.speed = flySpeed;
            [L addAnimation:g forKey:kCG27FlyInKey];
        }

        CGPoint C = [list convertPoint:spreadCenterW fromView:nil];
        double startScale = CG27FlyStartScale();
        for (UIView *iv in list.subviews) {
            if (![iv isKindOfClass:%c(SBIconView)] || iv.hidden) continue;
            CALayer *I = iv.layer;
            CAAnimation *old = CG27FlyAnimationAt(I, begin);
            CALayer *shown = I.presentationLayer ?: I;
            CGPoint shownPosition = shown.position;
            double shownZ = shown.zPosition;
            CGPoint positionVelocity = CG27FlyVelocity(I, old, @"position", begin);
            double currentZVelocity = CG27FlyVelocity(I, old, @"zPosition", begin).x;
            [I removeAnimationForKey:kCG27FlyInKey];
            CGPoint p = I.position, pw = [list convertPoint:p toView:nil];
            double t = fmin(hypot(pw.x - spreadCenterW.x, pw.y - spreadCenterW.y) / kCG27FlyMaxDistance, 1.0);
            double k = t * t * t / kCG27FlyZCurve;
            double response = fmax(fabs(flyIn ? kCG27FlyZResponse + k : kCG27FlyZResponse - k), 0.02);
            CGPoint out = CGPointMake(C.x + (p.x - C.x) * startScale, C.y + (p.y - C.y) * startScale);
            CGPoint positionFrom = old ? shownPosition : (flyIn ? out : p), positionTo = flyIn ? p : out;
            double currentZ = old ? shownZ : I.zPosition + zFrom, targetZ = I.zPosition + zTo;
            double vz = old ? currentZVelocity : zVelocity;
            double dx = positionTo.x - positionFrom.x, dy = positionTo.y - positionFrom.y;
            double distance2 = dx * dx + dy * dy;
            double vp = old ? (distance2 > 1e-6 ? (positionVelocity.x * dx + positionVelocity.y * dy) / distance2 : 0) : towardSpread;
            CASpringAnimation *z = CG27FlySpring(@"zPosition", @(currentZ), @(targetZ), response, zDamping,
                                                 fabs(targetZ - currentZ) > 1e-6 ? vz / (targetZ - currentZ) : 0);
            CASpringAnimation *spread = CG27FlySpring(@"position", [NSValue valueWithCGPoint:positionFrom],
                                                      [NSValue valueWithCGPoint:positionTo], spreadResponse, 1.0, vp);
            CAKeyframeAnimation *show = CG27FlyVisibility(currentZ, targetZ, vz, response, zDamping, z.duration);
            BOOL partBlur = backdrops && blurAnim && !CG27FlyIconHasBackdrop(iv) && !CG27FlyIconOverflows(iv);
            for (UIView *part in iv.subviews) {
                CALayer *PL = part.layer;
                [PL removeAnimationForKey:kCG27FlyInKey];
                CG27FlyRemoveBlur(PL);
                if (!partBlur) continue;
                CG27FlyAddBlur(PL, blur);
                CAKeyframeAnimation *pb = [blurAnim copy];
                pb.beginTime = begin; pb.fillMode = kCAFillModeBackwards;
                pb.speed = flySpeed;
                [PL addAnimation:pb forKey:kCG27FlyInKey];
            }
            CAAnimationGroup *g = [CAAnimationGroup animation];
            g.animations = flyIn ? @[z, spread, show] : @[spread, z, show];
            g.duration = fmax(z.duration, spread.duration); g.beginTime = begin; g.fillMode = kCAFillModeBackwards;
            g.speed = flySpeed;
            [I addAnimation:g forKey:kCG27FlyInKey];
            longest = fmax(longest, g.duration);
        }
    }
    if (dock) {
        dock.layer.opacity = 1;
        if (!CG27FlyDockSlide(!flyIn, begin, &longest) && !flyIn) dock.layer.opacity = 0;
    }
    [CATransaction commit];

    UIView *done = list;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((fmin(longest / flySpeed, 15) + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != gCG27FlyGeneration || !done) return;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CG27FlyResetList(done, YES);
        [CATransaction commit];
    });
}

static NSString *const kCG27SheetKeys[] = {
    @"sameWallpaperInitialTransitionSettings", @"sameWallpaperSubsequentTransitionSettings",
    @"differentWallpaperInitialTransitionSettings", @"differentWallpaperSubsequentTransitionSettings",
    @"overAppTransitionSettings",
};
static const void *kCG27SheetModeKey = &kCG27SheetModeKey;
static BOOL gCG27SheetBusy;

static BOOL CG27Sheet27Enabled(void) {
    return CG27Enabled() && CG27BoolPref(CFSTR("ClearSheet"), YES);
}

@interface SBCoverSheetSlidingViewController : UIViewController
- (UIViewFloatAnimatableProperty *)progressProperty;
@property (nonatomic) CGPoint lastTouchLocation;
@end

static const void *kCG27SheetCatchupAnchorKey = &kCG27SheetCatchupAnchorKey;

static NSNumber *CG27SheetCatchupAnchor(SBCoverSheetSlidingViewController *controller) {
    if (!NSThread.isMainThread || !(CG27Sheet27Enabled() || CG27FlyInEnabled()) ||
        ![controller isKindOfClass:%c(SBCoverSheetPrimarySlidingViewController)]) return nil;
    double p = controller.progressProperty.presentationValue;
    return isfinite(p) && p > -0.5 && p < 1.5 ? @(p) : nil;
}

%hook SBCoverSheetSlidingViewController
- (void)_presentGestureBeganWithGestureRecognizer:(id)gesture {
    id previous = objc_getAssociatedObject(self, kCG27SheetCatchupAnchorKey);
    objc_setAssociatedObject(self, kCG27SheetCatchupAnchorKey, CG27SheetCatchupAnchor((id)self), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        %orig;
    }
    @finally { objc_setAssociatedObject(self, kCG27SheetCatchupAnchorKey, previous, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}

- (void)_dismissGestureBeganWithGestureRecognizer:(id)gesture {
    id previous = objc_getAssociatedObject(self, kCG27SheetCatchupAnchorKey);
    objc_setAssociatedObject(self, kCG27SheetCatchupAnchorKey, CG27SheetCatchupAnchor((id)self), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        %orig;
    }
    @finally { objc_setAssociatedObject(self, kCG27SheetCatchupAnchorKey, previous, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}

- (void)_startCatchupAnimationWithDuration:(double)duration completion:(id)completion {
    NSNumber *anchor = objc_getAssociatedObject(self, kCG27SheetCatchupAnchorKey);
    if (anchor) {
        CGFloat height = self.view.bounds.size.height;
        if (isfinite(height) && height > 1) {
            CGPoint location = self.lastTouchLocation;
            location.y = (1 - anchor.doubleValue) * height;
            self.lastTouchLocation = location;
        }
    }
    %orig;
}
%end

static void CG27SheetApply27(id parent) {
    NSDictionary *home = @{
        @"blursPanel": @NO, @"panelWallpaper": @NO, @"scaleWallpaper": @NO, @"fadesContent": @NO,
        @"darkensContent": @NO, @"trackingWallpaper": @NO, @"orientPanelWallpaper": @NO, @"fadePanelWallpaper": @NO,
        @"fadesCoverSheetContent": @NO,
    };
    NSDictionary *overApp = @{
        @"blursPanel": @NO, @"panelWallpaper": @YES, @"trackingWallpaper": @YES, @"trackingWallpaperParallaxFactor": @0.0,
        @"fadePanelWallpaper": @YES, @"fadesContent": @NO, @"floatingLayerAsWallpaperOverlay": @NO,
    };
    for (NSUInteger i = 0; i < sizeof(kCG27SheetKeys) / sizeof(kCG27SheetKeys[0]); i++) {
        id child = nil;
        @try { child = [parent valueForKey:kCG27SheetKeys[i]]; } @catch (NSException *e) { continue; }
        if (!child) continue;
        NSMutableDictionary *values = [(i == 4 ? overApp : home) mutableCopy];
        if (i == 1 || i == 2) values[@"floatingLayerAsWallpaperOverlay"] = @NO;
        [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, __unused BOOL *stop) {
            @try { [child setValue:value forKey:key]; } @catch (NSException *e) {}
        }];
    }
}

static void CG27SheetSync(id parent) {
    if (gCG27SheetBusy || !parent) return;
    BOOL want = CG27Sheet27Enabled();
    NSNumber *mode = objc_getAssociatedObject(parent, kCG27SheetModeKey);
    if (mode && mode.boolValue == want) return;
    gCG27SheetBusy = YES;
    @try {
        if (mode.boolValue && !want && [parent respondsToSelector:@selector(setDefaultValues)])
            ((void (*)(id, SEL))objc_msgSend)(parent, @selector(setDefaultValues));
        if (want) CG27SheetApply27(parent);
    } @catch (NSException *e) {}
    gCG27SheetBusy = NO;
    objc_setAssociatedObject(parent, kCG27SheetModeKey, @(want), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook CSCoverSheetTransitionsSettings
- (void)setDefaultValues {
    %orig;
    if (!gCG27SheetBusy) objc_setAssociatedObject(self, kCG27SheetModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (id)sameWallpaperInitialTransitionSettings {
    CG27SheetSync(self);
    return %orig;
}
- (id)sameWallpaperSubsequentTransitionSettings {
    CG27SheetSync(self);
    return %orig;
}
- (id)differentWallpaperInitialTransitionSettings {
    CG27SheetSync(self);
    return %orig;
}
- (id)differentWallpaperSubsequentTransitionSettings {
    CG27SheetSync(self);
    return %orig;
}
- (id)overAppTransitionSettings {
    CG27SheetSync(self);
    return %orig;
}
%end

static BOOL CG27SheetTargetPortrait(void) {
    CGSize size = [UIScreen mainScreen].bounds.size;
    return fabs(size.width - 430.0) < 0.5 && fabs(size.height - 932.0) < 0.5;
}

%hook CSCoverSheetViewController
- (double)listMinY {
    double original = %orig;
    if (!CG27Sheet27Enabled() || !kCG27SheetClockOffsetEnabled || !CG27SheetTargetPortrait()) return original;
    SEL baseline = @selector(timeLabelBaselineY), gap = @selector(prominentBaselineToListY);
    if (![(id)self respondsToSelector:baseline] || ![(id)self respondsToSelector:gap]) return original;
    double b = ((double (*)(id, SEL))objc_msgSend)(self, baseline);
    double g = ((double (*)(id, SEL))objc_msgSend)(self, gap);
    return original + (256.6666666666667 - (b + g));
}
%end

%hook CSCombinedListViewController
- (double)horizontalInsetMargin {
    return CG27Sheet27Enabled() && CG27SheetTargetPortrait() ? 14.0 : %orig;
}
%end

%hook CSCoverSheetTransitionSettings
- (BOOL)iconsFlyIn {
    return CG27FlyInEnabled() ? NO : %orig;
}
%end

%hook SBCoverSheetPresentationManager
- (void)coverSheetSlidingViewController:(id)controller prepareForPresentationTransitionForUserGesture:(BOOL)gesture {
    %orig;
    gCG27FlyOutArmed = gesture && !gCG27FlyHidden && CG27FlyInEnabled() && CG27FlyHomeVisible();
}

- (void)coverSheetSlidingViewController:(id)controller prepareForDismissalTransitionForReversingTransition:(BOOL)reversing forUserGesture:(BOOL)gesture {
    %orig;
    gCG27FlyOutArmed = NO;
    if (!CG27FlyInEnabled()) { if (gCG27FlyHidden) CG27FlySetHidden(NO); return; }
    if (!gCG27FlyHidden && (reversing || !gCG27SheetSettledShown)) return;
    if (CG27FlyHomeVisible()) { if (!gCG27FlyHidden) CG27FlySetHidden(YES); }
    else if (gCG27FlyHidden) CG27FlySetHidden(NO);
}

- (void)coverSheetSlidingViewController:(id)controller committingToEndPresented:(BOOL)presented {
    %orig;
    BOOL armed = gCG27FlyOutArmed;
    gCG27FlyOutArmed = NO;
    if (!presented && !gCG27FlyHidden) return;
    if (presented && !armed) return;
    SEL vsel = NSSelectorFromString(@"_viewVelocity");
    double velocity = [controller respondsToSelector:vsel] ? ((double (*)(id, SEL))objc_msgSend)(controller, vsel) : 0;
    if (!CG27FlyInEnabled() || !CG27FlyHomeVisible()) { if (gCG27FlyHidden) CG27FlySetHidden(NO); return; }
    CG27FlyRun(!presented, velocity);
}

- (void)coverSheetSlidingViewControllerDidEndTransition:(id)controller {
    %orig;
    id manager = (id)self;
    BOOL presented = [manager respondsToSelector:@selector(isPresented)] && ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isPresented));
    gCG27SheetSettledShown = presented;
    if (gCG27FlyHidden && (!presented || !CG27FlyHomeVisible())) CG27FlySetHidden(NO);
}
%end

@interface SBFluidSwitcherItemContainer : UIView
@end

%hook SBFluidSwitcherItemContainer
- (void)setBounds:(CGRect)bounds {
    %orig;
    if (!gCG27Genies.count) return;
    id layout = [self respondsToSelector:@selector(appLayout)] ? [self appLayout] : nil;
    if (!layout) return;
    for (CG27GenieDriver *genie in [gCG27Genies copy])
        if (genie.native && genie.link && [genie.appLayout isEqual:layout]) { [genie nativeBounds:bounds of:self]; break; }
}
%end

%hook SBFluidSwitcherViewController

- (id)_itemContainerForAppLayoutIfExists:(id)appLayout {
    gCG27SwitcherVC = self;
    return %orig;
}

- (id)_iconForWorkspaceEntity:(id)entity {
    id original = %orig;
    if (original || !CG27AppEnabled() || !NSThread.isMainThread ||
        ![entity respondsToSelector:@selector(objectForActivationSetting:)]) return original;
    id identifier = [entity objectForActivationSetting:42];
    if (!identifier && [entity respondsToSelector:@selector(isDeviceApplicationSceneEntity)] &&
        [entity isDeviceApplicationSceneEntity]) {
        id scene = [entity deviceApplicationSceneEntity];
        id handle = [scene respondsToSelector:@selector(sceneHandle)] ? [scene sceneHandle] : nil;
        if ([handle respondsToSelector:@selector(lastActivationIconLeafIdentifier)])
            identifier = [handle lastActivationIconLeafIdentifier];
    }
    if (![identifier isKindOfClass:NSString.class] || ![identifier length]) return original;
    UIView *list = CG27FlyList();
    for (UIView *view in list.subviews) {
        if (![view isKindOfClass:%c(SBIconView)] || view.hidden || !view.window) continue;
        id icon = ((id (*)(id, SEL))objc_msgSend)(view, @selector(icon));
        if (![icon respondsToSelector:@selector(isWidgetIcon)] || ![icon isWidgetIcon] ||
            ![icon respondsToSelector:@selector(gridSizeClass)] || [icon gridSizeClass] != 1 ||
            ![icon respondsToSelector:@selector(leafIdentifier)] ||
            ![[icon leafIdentifier] isEqual:identifier]) continue;
        CGRect frame = [view convertRect:view.bounds toView:nil];
        if (!CGRectIsEmpty(frame) && !CGRectIsInfinite(frame) &&
            CGRectIntersectsRect(frame, view.window.bounds)) return icon;
    }
    return original;
}

- (double)homeScreenIconCornerRadiusForAppLayout:(id)appLayout {
    double radius = %orig;
    if (!CG27AppEnabled() || gCG27StockIconFrame > 0 || !isfinite(radius) || radius < 0) return radius;
    UIView *icon = [self iconViewForAppLayout:appLayout];
    if (!icon) return radius;
    CGRect corrected = [self _iconImageFrameForIconView:icon], stock;
    gCG27StockIconFrame++;
    @try {
        stock = [self _iconImageFrameForIconView:icon];
    } @finally { gCG27StockIconFrame--; }
    if (CGRectIsEmpty(stock) || CGRectIsEmpty(corrected) || !isfinite(stock.size.width) ||
        !isfinite(corrected.size.width) || stock.size.width < 1) return radius;
    double scale = corrected.size.width / stock.size.width;
    return isfinite(scale) && scale > 0 ? radius * scale : radius;
}

- (void)_performModifierMatchMoveToIconViewResponse:(id)response {
    gCG27StockIconFrame++;
    %orig;
    gCG27StockIconFrame--;
}

- (CGRect)_iconImageFrameForIconView:(UIView *)iconView {
    CGRect frame = %orig;
    if (!CG27AppEnabled() || gCG27StockIconFrame > 0 || CGRectIsEmpty(frame) || !iconView ||
        ![iconView respondsToSelector:@selector(iconImageFrame)])
        return frame;
    UIView *image = nil;
    Ivar iv = class_getInstanceVariable(object_getClass(iconView), "_iconImageView");
    if (iv && ivar_getTypeEncoding(iv)[0] == '@') image = object_getIvar(iconView, iv);
    if (![image isKindOfClass:UIView.class] || image.bounds.size.width < 1) return frame;
    CGRect unscaled = [(id)iconView iconImageFrame];
    if (unscaled.size.width < 1 || unscaled.size.height < 1) return frame;
    CGRect drawn = [image convertRect:image.bounds toView:iconView];
    double k = frame.size.width / unscaled.size.width;
    double dx = (CGRectGetMidX(drawn) - CGRectGetMidX(unscaled)) * k, dy = (CGRectGetMidY(drawn) - CGRectGetMidY(unscaled)) * k;
    double sx = drawn.size.width / unscaled.size.width, sy = drawn.size.height / unscaled.size.height;
    if (!isfinite(dx) || !isfinite(dy) || !isfinite(sx) || !isfinite(sy) || fabs(dx) > 24 || fabs(dy) > 24 ||
        sx < 0.4 || sx > 3 || fabs(sx - sy) > 1e-3) return frame;
    CGPoint center = CGPointMake(CGRectGetMidX(frame) + dx, CGRectGetMidY(frame) + dy);
    CGSize size = CGSizeMake(frame.size.width * sx, frame.size.height * sy);
    return CGRectMake(center.x - size.width / 2, center.y - size.height / 2, size.width, size.height);
}

%end

@interface SBAppSwitcherDomain : NSObject
+ (id)rootSettings;
@end

static id CG27AnimationSettings(void) {
    Class domain = %c(SBAppSwitcherDomain);
    id root = [domain respondsToSelector:@selector(rootSettings)] ? [domain rootSettings] : nil;
    id animation = nil;
    @try { animation = [root valueForKey:@"animationSettings"]; } @catch (NSException *e) {}
    return [animation isKindOfClass:%c(SBFluidSwitcherAnimationSettings)] ? animation : nil;
}

static NSString *const kCG27PrefsChanged = @"com.bazik1337.ios27animsreborn/changed";

static void CG27PrefsChanged(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name,
                             __unused const void *object, __unused CFDictionaryRef info) {
    CFPreferencesAppSynchronize(CFSTR("com.bazik1337.ios27animsreborn"));
    dispatch_async(dispatch_get_main_queue(), ^{
        gCG27PrefsLoaded = -1;
        NSMutableSet *all = [NSMutableSet setWithArray:gCG27AppliedSettings.allObjects];
        id animation = CG27AnimationSettings();
        if (animation) [all addObject:animation];
        [gCG27AppliedSettings removeAllObjects];
        for (id settings in all) {
            CG27RestoreStockSettings(settings);
            CG27ApplyIOS27Settings(settings);
        }
        if (!CG27FlyInEnabled() && gCG27FlyHidden) CG27FlySetHidden(NO);
    });
}

%ctor {
    %init;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CG27PrefsChanged,
                                    (__bridge CFStringRef)kCG27PrefsChanged, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    dispatch_async(dispatch_get_main_queue(), ^{
        CG27ApplyIOS27Settings(CG27AnimationSettings());
    });
}
