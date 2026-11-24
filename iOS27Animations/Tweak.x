#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/stat.h>
#include <os/lock.h>
#include "SpringMath.h"
#include "GenieEngine.h"
#include "../shared/HookCompatibility.h"
#if defined(DEBUG) && DEBUG
#define CG27_STARTUP_LOG "/var/mobile/Library/Logs/27anims-main-startup.log"
#endif
#include "../shared/AfterLaunch.h"

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
@end
@interface NSObject (CG27IconView)
- (CGRect)iconImageFrame;
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

extern float UIAnimationDragCoefficient(void);

static volatile double gCG27GlobalSlow = 1.0;

static double gCG27PrefsLoaded = -1;
static os_unfair_lock gCG27PrefsLock = OS_UNFAIR_LOCK_INIT;
static BOOL gCG27RuntimeReady;

static CFPropertyListRef CG27CopyPref(CFStringRef key) {
    static CFMutableDictionaryRef cache;
    os_unfair_lock_lock(&gCG27PrefsLock);
    double now = CACurrentMediaTime();
    if (!cache) cache = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (gCG27PrefsLoaded < 0 || now - gCG27PrefsLoaded > 0.5) { CFDictionaryRemoveAllValues(cache); gCG27PrefsLoaded = now; }
    CFPropertyListRef v = CFDictionaryGetValue(cache, key);
    if (!v) {
        v = CFPreferencesCopyAppValue(key, CFSTR("com.bazik1337.ios2627anims"));
        CFDictionarySetValue(cache, key, v ?: (CFPropertyListRef)kCFNull);
        if (v) CFRelease(v);
        v = CFDictionaryGetValue(cache, key);
    }
    CFPropertyListRef result = v == (CFPropertyListRef)kCFNull ? NULL : CFRetain(v);
    os_unfair_lock_unlock(&gCG27PrefsLock);
    return result;
}

static BOOL CG27BoolPref(CFStringRef key, BOOL fallback) {
    CFPropertyListRef v = CG27CopyPref(key);
    if (!v) return fallback;
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue((CFBooleanRef)v) : fallback;
    CFRelease(v);
    return on;
}

static BOOL CG27Enabled(void) {
    if (!gCG27RuntimeReady || !NSThread.isMainThread) return NO;
    if (UIAccessibilityIsReduceMotionEnabled()) return NO;
    return CG27BoolPref(CFSTR("Enabled"), NO);
}

static double CG27DoublePref(CFStringRef key, double fallback, double lo, double hi) {
    CFPropertyListRef v = CG27CopyPref(key);
    double f = fallback;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &f);
    if (v) CFRelease(v);
    return isfinite(f) && f >= lo && f <= hi ? f : fallback;
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

static double CG27SlowFactor(void) {
    return 1.0;
    CFPropertyListRef v = CG27CopyPref(CFSTR("SlowFactor"));
    double f = 1.0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &f);
    if (v) CFRelease(v);
    return f > 0.1 && f < 20 ? f : 1.0;
}

static const double kOpenDampingRatio = 1.0;
static const double kOpenResponse = 0.24;

static double CG27OpenResponse(void) {
    CFPropertyListRef speed = CG27CopyPref(CFSTR("OpenSpeed"));
    if (speed) {
        CFRelease(speed);
        return kOpenResponse / CG27DoublePref(CFSTR("OpenSpeed"), 1.0, 0.5, 2.0);
    }
    return CG27DoublePref(CFSTR("OpenResponse"), kOpenResponse, 0.1, 0.6);
}

static double CG27CloseScale(void) {
    return 1.0 / CG27DoublePref(CFSTR("CloseSpeed"), 1.0, 0.5, 2.0);
}

static BOOL CG27DropletEnabled(void) {
    return YES;
}
static const double kCloseResponse = 0.336;

static NSString *const kCG27CornerResetReason = @"iOS2627AnimsCornerRadiusReset";
static const double kOpenCornerResetDelay = 0.06;
static const double kCloseCornerResetDelay = 0.12;
static const NSUInteger kPhaseWillUpdate = 2;
static const void *kCG27CornerResetKey = &kCG27CornerResetKey;
static const void *kCG27StartedKey = &kCG27StartedKey;

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
    CFPropertyListRef v = CG27CopyPref(CFSTR("Intensity"));
    double f = 1.0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &f);
    if (v) CFRelease(v);
    return isfinite(f) && f >= 0 && f <= 3 ? f : 1.0;
}

@interface CG27GenieDriver : NSObject {
@public
    G27Genie _engine;
    double _shownXY[G27_V][2];
    BOOL _hasShownXY;
}
@property (nonatomic, weak) UIView *container;
@property (nonatomic, weak) UIView *accessory;
@property (nonatomic) int accessorySearches;
@property (nonatomic, strong) id appLayout;
@property (nonatomic) double startTime, lastTime, intensity;
@property (nonatomic) BOOL sawLayout;
@property (nonatomic) double renderedB;
@property (nonatomic) BOOL retargeted;
@property (nonatomic) BOOL accessoryOverflows;
@property (nonatomic, strong) NSHashTable<UIView *> *iconMeshViews;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, weak) id owner;
@property (nonatomic, strong) id previousMesh;
@property (nonatomic, strong) id appliedMesh;
@property (nonatomic, strong) NSHashTable<UIView *> *grabbers;
@property (nonatomic, weak) UIView *badge;
@property (nonatomic, strong) UIView *badgeCopy;
@property (nonatomic) int badgeSearches;
@property (nonatomic) double iconWidth;
@property (nonatomic) BOOL opening;
- (void)finish;
@end

static CG27GenieDriver *gCG27Genie;

static BOOL CG27SameFrame(CALayer *a, CALayer *b) {
    CGPoint p = a.position, q = b.position;
    CGSize s = a.bounds.size, t = b.bounds.size;
    return fabs(p.x - q.x) < 0.5 && fabs(p.y - q.y) < 0.5 && fabs(s.width - t.width) < 0.5 &&
        fabs(s.height - t.height) < 0.5 && CATransform3DEqualToTransform(a.transform, b.transform);
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
static NSArray<UIView *> *CG27OverflowingIcons(UIView *accessory) {
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
            if (!CGRectContainsRect(bounds, [v convertRect:v.bounds toView:accessory])) [found addObject:v];
            continue;
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return found;
}

static id CG27GestureLayoutSettings(id appLayout);
static void CG27EnsureIOS27Settings(id modifier);

static NSString *const kCG27GrabberHideKey = @"iOS2627AnimsGrabberHide";

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
static NSString *const kCG27MeshAnimationKey = @"iOS2627AnimsMesh";

@implementation CG27GenieDriver

- (void)start {
    self.startTime = self.lastTime = CACurrentMediaTime();
    if (self.link) return;
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    CG27RequestHighFrameRate(self.link, gCG27FrameRateReason);
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self.link invalidate];
    self.link = nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.container.layer removeAnimationForKey:kCG27MeshAnimationKey];
    [self.accessory.layer removeAnimationForKey:kCG27MeshAnimationKey];
    if (self.appliedMesh) self.container.layer.meshTransform = self.previousMesh;
    if (self.appliedMesh && !self.accessoryOverflows) self.accessory.layer.meshTransform = nil;
    for (UIView *icon in self.iconMeshViews.allObjects) {
        icon.layer.meshTransform = nil;
        CG27RestoreMeshRenderScale(icon.layer);
    }
    self.iconMeshViews = nil;
    self.appliedMesh = nil;
    self.previousMesh = nil;
    CG27ShowGrabbers(self.grabbers);
    self.grabbers = nil;
    [self.badgeCopy removeFromSuperview];
    self.badgeCopy = nil;
    [CATransaction commit];
}

- (id)meshForEngine:(const G27Genie *)g {
    double xy[G27_V][2];
    G27GenieMesh(g, g->b, xy);
    double gain = self.intensity;
    if (gain != 1.0)
        for (int k = 0; k < G27_V; k++) {
            xy[k][0] = (double)(k % G27_N) / (G27_N - 1) + gain * (xy[k][0] - (double)(k % G27_N) / (G27_N - 1));
            xy[k][1] = (double)(k / G27_N) / (G27_N - 1) + gain * (xy[k][1] - (double)(k / G27_N) / (G27_N - 1));
        }
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

- (void)applyMeshWithLead:(double)lead at:(double)showTime frame:(double)frame {
    G27Genie ahead = _engine;
    if (lead > 0 && lead < 0.05) G27GenieStep(&ahead, lead);
    self.renderedB = ahead.b;
    id mesh = [self meshForEngine:&ahead];
    G27GenieMesh(&ahead, ahead.b, _shownXY);
    for (int k = 0; k < G27_V && self.intensity != 1.0; k++) {
        _shownXY[k][0] = (double)(k % G27_N) / (G27_N - 1) + self.intensity * (_shownXY[k][0] - (double)(k % G27_N) / (G27_N - 1));
        _shownXY[k][1] = (double)(k / G27_N) / (G27_N - 1) + self.intensity * (_shownXY[k][1] - (double)(k / G27_N) / (G27_N - 1));
    }
    _hasShownXY = YES;
    CAKeyframeAnimation *prediction = nil;
    if (showTime > 0 && frame > 0.004 && frame < 0.034 && !G27GenieSettled(&ahead)) {
        int steps = (int)fmin(ceil(frame * 120 - 0.01), 2) * kCG27PredictFrames;
        double step = frame * kCG27PredictFrames / steps;
        NSMutableArray *values = [NSMutableArray arrayWithObject:mesh];
        NSMutableArray *times = [NSMutableArray arrayWithObject:@0];
        G27Genie future = ahead;
        for (int i = 1; i <= steps; i++) {
            G27GenieStep(&future, step);
            [values addObject:[self meshForEngine:&future]];
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
        accessory.layer.meshTransform = mesh;
        if (prediction) [accessory.layer addAnimation:prediction forKey:kCG27MeshAnimationKey];
        else [accessory.layer removeAnimationForKey:kCG27MeshAnimationKey];
    } else if (accessory) {
        [accessory.layer removeAnimationForKey:kCG27MeshAnimationKey];
        accessory.layer.meshTransform = nil;
        self.accessory = nil;
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
        self.previousMesh = [self.container.layer valueForKey:@"meshTransform"];
        if (self.previousMesh) { [self finish]; return; }
        self.grabbers = [NSHashTable weakObjectsHashTable];
        SBFluidSwitcherViewController *vc = CG27SwitcherVC();
        UIView *switcherView = vc.isViewLoaded ? vc.view : self.container.superview;
        if (switcherView) CG27CollectViews(switcherView, @"SBHomeGrabberView", 0, self.grabbers);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CG27HideGrabbers(self.grabbers);
        [CATransaction commit];
    }
    if (!self.container.window) { [self finish]; return; }
    if ([self.container respondsToSelector:@selector(appLayout)] &&
        ![[self.container appLayout] isEqual:self.appLayout]) { [self finish]; return; }
    if (!self.accessoryOverflows && !self.accessory && self.accessorySearches < 240) {
        self.accessorySearches++;
        self.accessory = CG27FindAccessory(self.container);
    }
    if (self.accessory) {
        NSArray<UIView *> *icons = CG27OverflowingIcons(self.accessory);
        if (icons.count) [self meshIcons:icons];
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
    [self advance:dt];
    if (!self.link) return;
    BOOL ownerRunning = self.owner && CG27UIntIvar(self.owner, "_transitionPhase") == kPhaseWillUpdate;
    if (G27GenieSettled(&_engine) && (!ownerRunning || now - self.startTime > 0.15)) { [self finish]; return; }
    BOOL tracking = self.sawLayout && self.owner &&
        CG27UIntIvar(self.owner, "_transitionPhase") == kPhaseWillUpdate;
    double frame = link.targetTimestamp - link.timestamp;
    [self applyMeshWithLead:tracking ? frame : 0 at:link.targetTimestamp frame:frame];
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

- (void)finish {
    [self stop];
    if (gCG27Genie == self) gCG27Genie = nil;
}

@end

static void CG27StartGenie(id modifier, BOOL opening, CGRect icon, id appLayout, double response, double zeta) {
    CGRect window = UIScreen.mainScreen.bounds;
    double W = window.size.width, H = window.size.height;
    double cx = CGRectGetMidX(icon), cy = CGRectGetMidY(icon), iw = icon.size.width;
    CG27GenieDriver *genie = gCG27Genie;
    UIView *current = genie.container ? [CG27SwitcherVC() _itemContainerForAppLayoutIfExists:appLayout] : nil;
    if (genie && genie.appLayout && [genie.appLayout isEqual:appLayout] && genie.link &&
        !G27GenieSettled(&genie->_engine) && (!genie.container || genie.container == current)) {
        G27GenieRetarget(&genie->_engine, !opening, cx, cy, iw, W, H, response, zeta);
        genie.owner = modifier;
        genie.startTime = CACurrentMediaTime();
        genie.lastTime = genie.startTime;
        genie.retargeted = YES;
        genie.opening = opening;
        genie.intensity = CG27Intensity();
        genie.sawLayout = NO;
        return;
    }
    [genie finish];
    genie = [CG27GenieDriver new];
    genie.owner = modifier;
    genie.appLayout = appLayout;
    genie.intensity = CG27Intensity();
    G27GenieStart(&genie->_engine, !opening, cx, cy, iw, W, H, response, zeta);
    genie.iconWidth = iw;
    genie.opening = opening;
    gCG27Genie = genie;
    [genie start];
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
    } else {
        tuned.response = tuned.response * slow * closeScale;
    }
    return tuned;
}

- (id)transitionWillBegin {
    objc_setAssociatedObject(self, kCG27StartedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kCG27CornerResetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return %orig;
}

- (id)handleTimerEvent:(SBTimerSwitcherModifierEvent *)event {
    id response = %orig;
    if (![event.reason isEqualToString:kCG27CornerResetReason]) return response;
    if (!CG27AppEnabled() || CG27UIntIvar(self, "_transitionPhase") != kPhaseWillUpdate) return response;
    objc_setAssociatedObject(self, kCG27CornerResetKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SBUpdateLayoutSwitcherEventResponse *update = [[%c(SBUpdateLayoutSwitcherEventResponse) alloc] initWithOptions:4 updateMode:3];
    return [%c(SBSwitcherModifierEventResponse) responseByAppendingResponse:update toResponse:response];
}

- (CG27CornerRadii)cornerRadiiForIndex:(NSUInteger)index {
    CG27CornerRadii radii = %orig;
    if (!CG27AppEnabled() || !CG27DropletEnabled() || ![self _isIndexZoomAppLayout:index]) return radii;
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
                CGRectIntersectsRect(icon, window) && window.size.height > window.size.width) {
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
@end
@interface SBMutableSwitcherAnimationAttributes : NSObject
- (id)layoutSettings;
- (void)setCornerRadiusSettings:(id)settings;
@end

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
    if (!CG27AppEnabled() || !CG27GenieEnabled() || ![attributes respondsToSelector:@selector(setCornerRadiusSettings:)] ||
        ![attributes respondsToSelector:@selector(layoutSettings)] || ![element respondsToSelector:@selector(appLayout)])
        return attributes;
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_appLayout");
    if (iv && [[element appLayout] isEqual:object_getIvar(self, iv)])
        [(SBMutableSwitcherAnimationAttributes *)attributes setCornerRadiusSettings:[attributes layoutSettings]];
    return attributes;
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

static double kCG27NoBounceResponseScale = 0.7;
static const double kCG27ZoomDownResponseMultiplier = 0.8;

static BOOL CG27GestureBounce(void) {
    CFPropertyListRef v = CG27CopyPref(CFSTR("GestureBounce"));
    BOOL on = !v || CFGetTypeID(v) != CFBooleanGetTypeID() || CFBooleanGetValue((CFBooleanRef)v);
    if (v) CFRelease(v);
    return on;
}

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
    if (!CG27GestureBounce()) {
        CG27SetSpring(s, @"homeGestureTopRowZoomDownPositionSettings", 1.0, 0.45 * kCG27NoBounceResponseScale, 0);
        CG27SetSpring(s, @"homeGestureTopRowZoomDownScaleSettings", 1.0, 0.55 * kCG27NoBounceResponseScale, 0);
        CG27SetSpring(s, @"homeGestureBottomRowZoomDownPositionSettings", 1.0, 0.55 * kCG27NoBounceResponseScale, 0);
        CG27SetSpring(s, @"homeGestureBottomRowZoomDownScaleSettings", 1.0, 0.55 * kCG27NoBounceResponseScale, 0);
    }
    CG27SetSpring(s, @"homeGestureCenterRowZoomUpSettings", -1, -1, 0);
    CG27SetSpring(s, @"homeGestureEdgeRowZoomUpSettings", -1, -1, 0);
    CG27SetSpring(s, @"homeScreenOpacitySettings", 1.0, 0.23, -1);
    CG27SetValue(s, @"wallpaperScaleInApplication", 1.0);
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
    double ratio = CG27GestureBounce() ? 0.8 : 1.0;
    BOOL known = [gCG27AppliedSettings containsObject:animation];
    if (known && fabs(probe.dampingRatio - ratio) < 0.001 && probe.retargetImpulse == 0) return;
    CG27ApplyIOS27Settings(animation);
}

enum { kCG27ZoomSpringOther = 0, kCG27ZoomSpringPosition, kCG27ZoomSpringScale };
static int gCG27ZoomSpringKind;

%hook SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier
- (id)_positionSettings {
    gCG27ZoomSpringKind = kCG27ZoomSpringPosition;
    id settings = %orig;
    gCG27ZoomSpringKind = kCG27ZoomSpringOther;
    return settings;
}

- (id)_scaleSettings {
    gCG27ZoomSpringKind = kCG27ZoomSpringScale;
    id settings = %orig;
    gCG27ZoomSpringKind = kCG27ZoomSpringOther;
    return settings;
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
        if (!CG27GestureBounce()) {
            ratioTop = ratioBottom = 1.0;
            responseTop *= kCG27NoBounceResponseScale;
            responseBottom *= kCG27NoBounceResponseScale;
        }
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
static const double kCG27FlySpreadResponse = 0.36, kCG27FlySpreadExtra = 0.7, kCG27FlyCenterLift = 16.0;
static const double kCG27FlyBlurIn = 6.0, kCG27FlyBlurOut = 10.0;
static const double kCG27FlyDockResponse = 0.547826087, kCG27FlyDockDamping = 0.74, kCG27FlyDockOffscreen = 4.0;
static NSString *const kCG27FlyInKey = @"iOS2627AnimsFlyIn";

static BOOL gCG27FlyHidden;
static BOOL gCG27FlyOutArmed;
static BOOL gCG27SheetSettledShown = YES;
static NSInteger gCG27FlyGeneration;

static double CG27FlyStrength(void) {
    return CG27DoublePref(CFSTR("FlyStrength"), 1.0, 0, 3);
}

static double CG27FlySpreadExtra(void) {
    return kCG27FlySpreadExtra * CG27FlyStrength();
}

static double CG27FlySpreadResponse(void) {
    return kCG27FlySpreadResponse * fmax(1.0, CG27FlyStrength());
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
            gCG27FlyDockModifier = [root beginModifyingDockOffscreenFractionForReason:@"iOS2627AnimsFlyIn"];
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
    a.fillMode = kCAFillModeBackwards;
    return a;
}

static void CG27FlyCollect(UIView *v, int depth, NSMapTable<UIView *, NSNumber *> *ys) {
    if (depth > 7 || v.hidden) return;
    [ys setObject:@([v convertPoint:CGPointZero toView:nil].y) forKey:v];
    for (UIView *c in v.subviews) CG27FlyCollect(c, depth + 1, ys);
}

static BOOL CG27FlyDockSlide(BOOL offscreen, double begin, double *longest) {
    UIView *rootView = CG27FlyRoot().view;
    if (!rootView || (!offscreen && !gCG27FlyDockModifier)) return NO;
    NSMapTable<UIView *, NSNumber *> *before = [NSMapTable strongToStrongObjectsMapTable], *after = [NSMapTable strongToStrongObjectsMapTable];
    CG27FlyCollect(rootView, 0, before);
    if (!CG27FlyDockOffscreen(offscreen)) return NO;
    CG27FlyCollect(rootView, 0, after);
    for (UIView *v in before) {
        NSNumber *y1 = [after objectForKey:v];
        if (!y1) continue;
        double d = [before objectForKey:v].doubleValue - y1.doubleValue;
        if (fabs(d) < 0.5) continue;
        UIView *sup = v.superview;
        NSNumber *s0 = sup ? [before objectForKey:sup] : nil, *s1 = sup ? [after objectForKey:sup] : nil;
        if (s0 && s1 && fabs((s0.doubleValue - s1.doubleValue) - d) < 0.5) continue;
        CASpringAnimation *slide = CG27FlySpring(@"position.y", @(d), @0, kCG27FlyDockResponse, kCG27FlyDockDamping, 0);
        slide.additive = YES;
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
    list.layer.filters = nil;
    if (!keepAnimations) [list.layer removeAnimationForKey:kCG27FlyInKey];
    for (UIView *iv in list.subviews) {
        if (![iv isKindOfClass:%c(SBIconView)]) continue;
        if (!keepAnimations) [iv.layer removeAnimationForKey:kCG27FlyInKey];
        for (UIView *part in iv.subviews) {
            if (!keepAnimations) [part.layer removeAnimationForKey:kCG27FlyInKey];
            part.layer.filters = nil;
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

static double CG27FlyCrossing(double response, double damping, double level) {
    double x = 1, v = 0, t = 0, dt = 1.0 / 480;
    while (x > level && t < 3) { G27SpringStep(&x, &v, 0, response, damping, dt); t += dt; }
    return t;
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
    CGPoint spreadCenterW = CGPointMake(W.width / 2, W.height / 2 - kCG27FlyCenterLift);
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
        [L removeAnimationForKey:kCG27FlyInKey];
        CG27FlyTouch(list);
        L.filters = nil;
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
        double sTarget = flyIn ? 1 : 0, s = 1 - sTarget, sv = spreadVelocity, dt = 1.0 / 60, R = flyIn ? kCG27FlyBlurIn : kCG27FlyBlurOut;
        const int n = 75;
        for (int i = 0; i <= n; i++) {
            double si = i == n ? sTarget : fmin(fmax(s, 0), 1);
            [radii addObject:@(R * (1 - si))];
            [alphas addObject:@(si * si)];
            G27SpringStep(&s, &sv, sTarget, spreadResponse, 1, dt);
        }
        NSMutableArray *anims = [NSMutableArray array];
        CAFilter *blur = [%c(CAFilter) filterWithType:@"gaussianBlur"];
        CAKeyframeAnimation *blurAnim = nil;
        if (blur) {
            [blur setValue:@"gaussianBlur" forKey:@"name"];
            [blur setValue:@(flyIn ? 0 : R) forKey:@"inputRadius"];
            blurAnim = [CAKeyframeAnimation animationWithKeyPath:@"filters.gaussianBlur.inputRadius"];
            blurAnim.values = radii; blurAnim.duration = n * dt;
            if (!backdrops) { L.filters = @[blur]; [anims addObject:blurAnim]; }
        }
        if (!flyIn) {
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
        double m = 1 + CG27FlySpreadExtra();
        double visibleZ = kCG27FlyCameraDistance * 0.98 / kCG27FlyFarZ;
        for (UIView *iv in list.subviews) {
            if (![iv isKindOfClass:%c(SBIconView)] || iv.hidden) continue;
            CALayer *I = iv.layer;
            [I removeAnimationForKey:kCG27FlyInKey];
            CGPoint p = I.position, pw = [list convertPoint:p toView:nil];
            double t = fmin(hypot(pw.x - spreadCenterW.x, pw.y - spreadCenterW.y) / kCG27FlyMaxDistance, 1.0);
            double k = t * t * t / kCG27FlyZCurve;
            double response = fmax(fabs(flyIn ? kCG27FlyZResponse + k : kCG27FlyZResponse - k), 0.02);
            CGPoint out = CGPointMake(C.x + (p.x - C.x) * m, C.y + (p.y - C.y) * m);
            CASpringAnimation *z = CG27FlySpring(@"zPosition", @(I.zPosition + zFrom), @(I.zPosition + zTo), response, zDamping,
                                                 zVelocity / (zTo - zFrom));
            CASpringAnimation *spread = CG27FlySpring(@"position", [NSValue valueWithCGPoint:flyIn ? out : p],
                                                      [NSValue valueWithCGPoint:flyIn ? p : out], spreadResponse, 1.0, towardSpread);
            double cross = CG27FlyCrossing(response, zDamping, flyIn ? visibleZ : 1 - visibleZ);
            CAKeyframeAnimation *show = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            show.values = flyIn ? @[@0, @1] : @[@1, @0];
            show.keyTimes = @[@0, @(fmin(cross / z.duration, 1)), @1];
            show.calculationMode = kCAAnimationDiscrete;
            show.duration = z.duration;
            BOOL partBlur = backdrops && blurAnim && !CG27FlyIconHasBackdrop(iv) && !CG27FlyIconOverflows(iv);
            for (UIView *part in iv.subviews) {
                CALayer *PL = part.layer;
                [PL removeAnimationForKey:kCG27FlyInKey];
                PL.filters = nil;
                if (!partBlur) continue;
                PL.filters = @[blur];
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
        [dock.layer removeAnimationForKey:kCG27FlyInKey];
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

%hook CSCoverSheetTransitionSettings
- (BOOL)iconsFlyIn {
    return CG27FlyInEnabled() ? NO : %orig;
}
%end

static void CG27CoverSheetDidEnd(id manager) {
    BOOL presented = [manager respondsToSelector:@selector(isPresented)] && ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isPresented));
    gCG27SheetSettledShown = presented;
    if (gCG27FlyHidden && (!presented || !CG27FlyHomeVisible())) CG27FlySetHidden(NO);
}

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
    CG27CoverSheetDidEnd(self);
}

- (void)_cleanupATransition {
    %orig;
    // iOS 15 has this cleanup method instead of the newer delegate callback.
    if (@available(iOS 16.0, *)) return;
    CG27CoverSheetDidEnd(self);
}
%end

%hook SBFluidSwitcherViewController

- (id)_itemContainerForAppLayoutIfExists:(id)appLayout {
    gCG27SwitcherVC = self;
    return %orig;
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
    if (unscaled.size.width < 1) return frame;
    CGRect drawn = [image convertRect:image.bounds toView:iconView];
    double k = frame.size.width / unscaled.size.width;
    double dx = (CGRectGetMidX(drawn) - CGRectGetMidX(unscaled)) * k, dy = (CGRectGetMidY(drawn) - CGRectGetMidY(unscaled)) * k;
    if (!isfinite(dx) || !isfinite(dy) || fabs(dx) > 24 || fabs(dy) > 24 || (fabs(dx) < 0.01 && fabs(dy) < 0.01)) return frame;
    return CGRectOffset(frame, dx, dy);
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

static NSString *const kCG27PrefsChanged = @"com.bazik1337.ios2627anims/changed";

static void CG27PrefsChanged(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name,
                             __unused const void *object, __unused CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gCG27RuntimeReady) return;
        CFPreferencesAppSynchronize(CFSTR("com.bazik1337.ios2627anims"));
        os_unfair_lock_lock(&gCG27PrefsLock);
        gCG27PrefsLoaded = -1;
        os_unfair_lock_unlock(&gCG27PrefsLock);
        gCG27GlobalSlow = CG27DoublePref(CFSTR("GlobalSlow"), 1.0, 1.0, 10.0);
        NSMutableSet *all = [NSMutableSet setWithArray:gCG27AppliedSettings.allObjects ?: @[]];
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

%hookf(float, UIAnimationDragCoefficient) {
    float drag = %orig;
    double k = gCG27GlobalSlow;
    return k > 1.001 ? (float)(drag * k) : drag;
}

static void CG27InstallHooks(void) {
    CG27StartupTrace("feature hooks begin");
    %init;
    CG27StartupTrace("feature hooks installed");
    gCG27RuntimeReady = YES;
    gCG27GlobalSlow = CG27DoublePref(CFSTR("GlobalSlow"), 1.0, 1.0, 10.0);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CG27PrefsChanged,
                                    (__bridge CFStringRef)kCG27PrefsChanged, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CG27ApplyIOS27Settings(CG27AnimationSettings());
    CG27StartupTrace("ready");
}

%group CG27Startup
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    CG27StartupTrace("SpringBoard launch callback finished");
    CG27AfterLaunch(^{ CG27InstallHooks(); });
}
%end
%end

%ctor {
    CG27StartupTrace("constructor entered");
    %init(CG27Startup);
    CG27StartupTrace("launch hook installed");
}
