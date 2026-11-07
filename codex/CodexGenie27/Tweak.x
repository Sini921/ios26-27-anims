// iOS 26-27 Anims by @bazik1337 — iOS 26/27 app open/close animation on iOS 16 (SpringBoard).
// Animation values measured on iOS 27.0 (24A435).

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/stat.h>
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

// ProMotion: SpringBoard's own display links pair the 80-120 Hz range with a high-frame-rate reason
// (-[SBDashBoardSetupView _createDisplayLink], SBFluidSwitcherAnimationSettings: 0x110001+). Without a reason
// the request is not honoured and the link runs at 60 Hz while the window animates at 120, so the mesh lags the
// crop every other frame. "Always 120 Hz" tweaks used to hide this.
@interface CADisplayLink (CG27Private)
- (void)setHighFrameRateReason:(unsigned int)reason;
@end

static const unsigned int kCG27DefaultFrameRateReason = 0x110001; // switcher layoutSettings
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
// Must append through this subclass: the composite it builds responds to -type, which
// SBFluidSwitcherRootSwitcherModifier calls on every response (the base class does not).
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

typedef struct { double topLeft, bottomLeft, bottomRight, topRight; } CG27CornerRadii;

extern float UIAnimationDragCoefficient(void); // returns float, not double

// Settings pane "slow down all animations" (GlobalSlow, 1-5): multiplies UIKit's animation drag coefficient in
// SpringBoard, the same switch as the system's slow-animations debug mode, so every SpringBoard animation (and the
// genie, which follows it) slows down alike. Read on any thread, so it is a plain value refreshed on the main
// thread when the preferences change.
static volatile double gCG27GlobalSlow = 1.0;

// Preferences are read on every display frame by the genie driver; cfprefs lookups are cached for 0.5 s
// (changes made with `defaults write` still apply within half a second).
// The Settings pane posts kCG27PrefsChanged; the handler resets gCG27PrefsLoaded so the next read is fresh.
static double gCG27PrefsLoaded = -1;

static CFPropertyListRef CG27CopyPref(CFStringRef key) {
    static CFMutableDictionaryRef cache;
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
    return v == (CFPropertyListRef)kCFNull ? NULL : CFRetain(v);
}

static BOOL CG27BoolPref(CFStringRef key, BOOL fallback) {
    CFPropertyListRef v = CG27CopyPref(key);
    if (!v) return fallback;
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue((CFBooleanRef)v) : fallback;
    CFRelease(v);
    return on;
}

// Kill switch: `defaults`-style domain com.bazik1337.ios2627anims, key Enabled (default YES).
static BOOL CG27Enabled(void) {
    if (UIAccessibilityIsReduceMotionEnabled()) return NO;
    return CG27BoolPref(CFSTR("Enabled"), YES);
}

// Numeric pref clamped to [lo, hi] (fallback outside it or when unset).
static double CG27DoublePref(CFStringRef key, double fallback, double lo, double hi) {
    CFPropertyListRef v = CG27CopyPref(key);
    double f = fallback;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &f);
    if (v) CFRelease(v);
    return isfinite(f) && f >= lo && f <= hi ? f : fallback;
}

// App open/close (zoom springs, droplet corners, genie). Key AppAnimations (default YES); independent of the
// cover sheet icon fly-in (IconFlyIn), so either can be used alone.
static BOOL CG27AppEnabled(void) {
    return CG27Enabled() && CG27BoolPref(CFSTR("AppAnimations"), YES);
}

// Reads a scalar ivar by name (MSHookIvar is C++-only).
static NSUInteger CG27UIntIvar(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return NSNotFound;
    const char *type = ivar_getTypeEncoding(iv);
    if (!type || (strcmp(type, @encode(NSUInteger)) && strcmp(type, @encode(NSInteger)))) return NSNotFound;
    return *(NSUInteger *)((uint8_t *)(__bridge void *)obj + ivar_getOffset(iv));
}

// Debug: SlowFactor (default 1) stretches all zoom springs and the droplet delay so the effect is visible.
static double CG27SlowFactor(void) {
    CFPropertyListRef v = CG27CopyPref(CFSTR("SlowFactor"));
    double f = 1.0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &f);
    if (v) CFRelease(v);
    return f > 0.1 && f < 20 ? f : 1.0;
}

// iOS 27 open spring: genieFullScreen{Center,Edge}RowZoomUpSettings = dampingRatio 1.0, response 0.24.
static const double kOpenDampingRatio = 1.0;
static const double kOpenResponse = 0.24;

// Settings pane tuning. OpenResponse: the open spring (iOS 27 = 0.24 s). CloseSpeed: divides every close spring
// (tap and swipe; 1 = iOS 27). Droplet: the round "droplet" corners at the start of a transition.
static double CG27OpenResponse(void) {
    return CG27DoublePref(CFSTR("OpenResponse"), kOpenResponse, 0.1, 0.6);
}

static double CG27CloseScale(void) {
    return 1.0 / CG27DoublePref(CFSTR("CloseSpeed"), 1.0, 0.5, 2.0);
}

static BOOL CG27DropletEnabled(void) {
    return CG27BoolPref(CFSTR("Droplet"), YES);
}
static const double kCloseResponse = 0.336; // iOS 27 and iOS 16 close spring

// iOS 27 "droplet": while the transition animates, the window's corner radius is half of its
// shorter side (215 pt); a timer then resets it (open after 0.06 s, close after 0.12 s:
// genieCornerRadiusTo{App,Home}ResetDelay) and asks for a layout update (options 4, updateMode 3).
static NSString *const kCG27CornerResetReason = @"iOS2627AnimsCornerRadiusReset";
static const double kOpenCornerResetDelay = 0.06;
static const double kCloseCornerResetDelay = 0.12;
static const NSUInteger kPhaseWillUpdate = 2; // SBTransitionPhase: 1 begin, 2 update, 3 end
static const void *kCG27CornerResetKey = &kCG27CornerResetKey;
static const void *kCG27StartedKey = &kCG27StartedKey;

static double CG27TimeScale(void) {
    double drag = UIAnimationDragCoefficient();
    return CG27SlowFactor() * (isfinite(drag) && drag > 0 ? drag : 1);
}


// ---------------------------------------------------------------------------------------------
// iOS 27 genie: 9 vertex springs + bounds-progress spring (GenieEngine.h, decoded from SpringBoard 27.0),
// applied as a 3x3 mesh to iOS 16's animated item container (which already supplies the crop/scale).
static BOOL CG27GenieEnabled(void) {
    CFPropertyListRef v = CG27CopyPref(CFSTR("Genie"));
    if (!v) return YES;
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue((CFBooleanRef)v) : YES;
    CFRelease(v);
    return on;
}

// SnowBoard's Custom Icon Scale can make the rendered icon larger than the switcher's icon-overlay layer.
// A meshTransform clips that entire layer to its original square, cutting off the scaled icon during
// app open/close. Keep the genie on the app window but let SpringBoard draw the icon overlay unmeshed.
static BOOL CG27PreserveScaledIconOverlay(void) {
    CFStringRef domain = CFSTR("com.spark.snowboardprefs");
    CFPropertyListRef enabled = CFPreferencesCopyAppValue(CFSTR("CustomIconSizeEnabled"), domain);
    BOOL on = enabled && CFGetTypeID(enabled) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)enabled);
    if (enabled) CFRelease(enabled);
    if (!on) return NO;
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("CustomIconSize"), domain);
    double scale = 1.0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &scale);
    if (value) CFRelease(value);
    return isfinite(scale) && fabs(scale - 1.0) > 0.01;
}

static __weak SBFluidSwitcherViewController *gCG27SwitcherVC;

// gCG27SwitcherVC is only learned when SpringBoard itself asks for an item container; until then (or after the switcher
// controller is rebuilt) every genie gave up after 0.2 s without a container. Fall back to the main switcher's content.
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

// Debug/taste: Intensity (default 1 = exact iOS 27) scales the mesh deviation from the plain grid.
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
    double _shownXY[G27_V][2];   // mesh on screen (unit square of the container), for the badge copy
    BOOL _hasShownXY;
}
@property (nonatomic, weak) UIView *container;
// The icon crossfade (SBFluidSwitcherIconOverlayView) lives in a sibling SBFluidSwitcherSpaceOverlayAccessoryView
// with the container's exact frame; it gets the same mesh so the icon fades in inside the genie shape (iOS 27
// keeps both inside SBSwitcherGenieEffectView) instead of as a plain square around the deformed window.
@property (nonatomic, weak) UIView *accessory;
@property (nonatomic) int accessorySearches;
@property (nonatomic, strong) id appLayout;
@property (nonatomic) double startTime, lastTime, intensity;
@property (nonatomic) BOOL sawLayout;
@property (nonatomic) double renderedB;
@property (nonatomic) BOOL retargeted;
@property (nonatomic) BOOL preserveScaledIconOverlay;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, weak) id owner;
@property (nonatomic, strong) id previousMesh;
@property (nonatomic, strong) id appliedMesh;
// Home indicators hidden while the genie runs: they are separate views at the bottom of the screen and do not
// follow the deformed window.
@property (nonatomic, strong) NSHashTable<UIView *> *grabbers;
// iOS 27 keeps the crossfade icon's badge visible, sticking out of the window's corner. Our mesh crops everything to
// the layer's unit square, so the badge is drawn by an unmeshed copy that follows the deformed top-right corner.
@property (nonatomic, weak) UIView *badge;
@property (nonatomic, strong) UIView *badgeCopy;
@property (nonatomic) int badgeSearches;
@property (nonatomic) double iconWidth;   // the home screen icon the window lands in
@property (nonatomic) BOOL opening;
- (void)finish;
@end

static CG27GenieDriver *gCG27Genie;
#if CG27_TEST_HOOKS
// Debug builds: events go to memory (Frida: CG27TestEvents) and to /var/mobile/Library/Logs/cg27.log, together with a
// per-frame trace of the genie's window, so a test can run without Frida attached.
static NSMutableString *gCG27Events;
static FILE *gCG27LogFile;
static FILE *CG27Log(void) {
    if (!gCG27LogFile) {
        // The per-frame trace grows by megabytes an hour: start over once it passes 16 MB.
        const char *path = "/var/mobile/Library/Logs/cg27.log";
        struct stat st;
        BOOL big = stat(path, &st) == 0 && st.st_size > (16 << 20);
        gCG27LogFile = fopen(path, big ? "w" : "a");
    }
    return gCG27LogFile;
}
#define CG27Event(...) do { NSString *line_ = [NSString stringWithFormat:__VA_ARGS__]; \
    if (!gCG27Events) gCG27Events = [NSMutableString string]; \
    [gCG27Events appendFormat:@"%.3f %@\n", CACurrentMediaTime(), line_]; \
    if (CG27Log()) { fprintf(CG27Log(), "%.3f %s\n", CACurrentMediaTime(), line_.UTF8String); fflush(CG27Log()); } } while (0)
#define CG27Trace(...) do { if (CG27Log()) { fprintf(CG27Log(), "%.3f ", CACurrentMediaTime()); fprintf(CG27Log(), __VA_ARGS__); fputc('\n', CG27Log()); } } while (0)
#else
#define CG27Event(...) do {} while (0)
#define CG27Trace(...) do {} while (0)
#endif

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
static id CG27GestureLayoutSettings(id appLayout);

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

// Back to the grabber's own alpha with a short fade.
static void CG27ShowGrabbers(NSHashTable<UIView *> *grabbers) {
    for (UIView *g in grabbers) {
        if (![g.layer animationForKey:kCG27GrabberHideKey]) continue;
        // The genie draws a separate badge copy while the original is hidden. Both must switch
        // in the same transaction when the mesh ends; fading the original after removing the
        // copy makes the notification count disappear briefly on swipe-to-home.
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
    // CALayer copies the mesh on set, so identity checks never match: restore whenever we applied one.
    [self.container.layer removeAnimationForKey:kCG27MeshAnimationKey];
    [self.accessory.layer removeAnimationForKey:kCG27MeshAnimationKey];
    if (self.appliedMesh) self.container.layer.meshTransform = self.previousMesh;
    if (self.appliedMesh) self.accessory.layer.meshTransform = nil;
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

// The mesh is computed on the main thread, but SpringBoard's own main thread stalls for 20-40 ms when a
// transition starts (app activation; measured the same with the tweak off) while the window keeps moving in
// the render server. So besides the model value, each frame hands the render server the predicted meshes of
// the next kCG27PredictFrames frames as a discrete keyframe animation; the next tick replaces it, and a stall
// plays the prediction instead of freezing the shape.

- (void)applyMeshWithLead:(double)lead at:(double)showTime frame:(double)frame {
    // The presentation crop we synced to belongs to the frame on screen now; the mesh will be shown on
    // the next one, so render the engine `lead` seconds ahead (one display frame).
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
        // Keyframes at most 1/120 s apart: when our link gets 60 Hz while the window animates at 120 (Low Power Mode
        // ends, a missed frame-rate request), the render server shows the in-between meshes instead of holding one
        // shape for two window frames. Same horizon as kCG27PredictFrames link frames.
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
        // Discrete keyframes take one more key time than values: the last mesh holds until the end.
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
    if (accessory && CG27SameFrame(accessory.layer, layer)) {
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
    // The genie outlives its transition phase only to settle (as on iOS 27); a hard cap guards against leaks.
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
        // Only the switcher's own tree: walking every SpringBoard window (home screen included) cost a main-thread
        // stall right when the animation starts.
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
    if (!self.preserveScaledIconOverlay && !self.accessory && self.accessorySearches < 240) {
        self.accessorySearches++;
        self.accessory = CG27FindAccessory(self.container);
    }
    // The icon crossfade in the accessory carries the badge, which sticks out of the icon (x 49, y -11 on 64 pt) and
    // would be cut by the mesh. The crossfade icon can be added after the accessory is found, so look every frame
    // until the badge shows up: the original is hidden and, when closing, an unmeshed copy drawn (see badgeCopy).
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
#if CG27_TEST_HOOKS
    CALayer *SP = self.container.layer.presentationLayer ?: self.container.layer;
    CG27Trace("win %p %s pos %.1f %.1f s %.3f h %.0f b %.3f bt %.0f mesh %d", self, self.opening ? "open" : "close",
              SP.position.x, SP.position.y, hypot(SP.transform.m11, SP.transform.m12), SP.bounds.size.height, _engine.b,
              _engine.bTarget, self.appliedMesh != nil);
#endif
    double dt = fmax(0, now - self.lastTime);
    self.lastTime = now;
    [self advance:dt];
    if (!self.link) return; // finished inside advance
    BOOL ownerRunning = self.owner && CG27UIntIvar(self.owner, "_transitionPhase") == kPhaseWillUpdate;
    if (G27GenieSettled(&_engine) && (!ownerRunning || now - self.startTime > 0.15)) { [self finish]; return; }
    BOOL tracking = self.sawLayout && self.owner &&
        CG27UIntIvar(self.owner, "_transitionPhase") == kPhaseWillUpdate;
    double frame = link.targetTimestamp - link.timestamp;
    [self applyMeshWithLead:tracking ? frame : 0 at:link.targetTimestamp frame:frame];
    [self placeBadgeCopy];
}

// Snapshot of the badge, drawn above the meshed accessory. Material-based badges
// can supply a live copy because renderInContext cannot capture backdrop layers.
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

// Badge copy: the badge's offset from the icon's top-right corner, hung on that corner of the deformed mesh, in the
// accessory's on-screen (presentation) geometry; alpha = the crossfade's.
- (void)placeBadgeCopy {
    UIView *copy = self.badgeCopy, *badge = self.badge, *acc = self.accessory;
    if (!copy) return;
    if (self.opening || !badge || !acc || !_hasShownXY || !copy.superview) { copy.layer.opacity = 0; return; }
    CALayer *AP = acc.layer.presentationLayer ?: acc.layer, *SP = copy.superview.layer.presentationLayer ?: copy.superview.layer;
    CGRect ab = acc.bounds;
    CGRect r = [badge convertRect:badge.bounds toView:acc];
    // top-right vertex of the mesh (row 0, column N-1), in accessory bounds coordinates
    const double *tr = _shownXY[G27_N - 1];
    CGPoint corner = CGPointMake(ab.origin.x + tr[0] * ab.size.width, ab.origin.y + tr[1] * ab.size.height);
    CGPoint o = CGPointMake(corner.x + (CGRectGetMinX(r) - CGRectGetMaxX(ab)), corner.y + (CGRectGetMinY(r) - CGRectGetMinY(ab)));
    CGPoint e = CGPointMake(o.x + r.size.width, o.y + r.size.height);
    CGPoint so = [AP convertPoint:o toLayer:SP], se = [AP convertPoint:e toLayer:SP];
    // 16 fades the crossfade icon in right at release, while the window is still big: following that alpha put a
    // huge badge over the app. The copy fades in with the window's size instead: invisible at twice the icon's
    // width, fully shown once the window is icon-sized (27 shows the badge only as the window turns into the icon).
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

// iOS 27 drives the bounds progress with the same spring as the window frame, so the counter-scale always
// matches the crop. iOS 16's frame spring differs (close is slower, open starts a frame later), so the
// engine follows the container's live crop: b_measured = (H - h) / (H - w) of the presentation bounds.
- (void)advance:(double)dt {
    CALayer *layer = self.container.layer.presentationLayer ?: self.container.layer;
    CGSize size = layer.bounds.size, screen = UIScreen.mainScreen.bounds.size;
    double H = screen.height, w = size.width, h = size.height;
    BOOL valid = w > 1 && H > w + 1 && h > w - 1 && h < H + 1 && fabs(w - screen.width) < 1;
    double bMeas = valid ? G27Clamp((H - h) / (H - w), 0, 1) : NAN;
    // Before the zoom layout lands, an opening container still has the full window bounds.
    if (valid && !self.sawLayout) {
        if (!self.retargeted && _engine.bTarget == 0 && h > H - 0.5) return;
        else self.sawLayout = YES;
    }
    if (!valid) { G27GenieStep(&_engine, dt); return; }
    BOOL ownerRunning = self.owner && CG27UIntIvar(self.owner, "_transitionPhase") == kPhaseWillUpdate;
    // FollowBounds itself falls back to wall-clock time while a reversed crop still moves away from
    // the target, so retargeted genies stay locked to the window too.
    if (!ownerRunning) G27GenieStep(&_engine, dt);
    else G27GenieFollowBounds(&_engine, bMeas, dt);
}

- (void)finish {
    CG27Event(@"finish %p opening %d", self, self.opening);
    [self stop];
    if (gCG27Genie == self) gCG27Genie = nil;
}

@end

// Starts (or retargets, when the same app's genie is still in flight) the genie for a zoom modifier.
static void CG27StartGenie(id modifier, BOOL opening, CGRect icon, id appLayout, double response, double zeta) {
    CG27Event(@"start %s %p icon %@ R %.3f z %.2f cur %p", opening ? "open" : "close", appLayout, NSStringFromCGRect(icon), response, zeta, gCG27Genie);
    CGRect window = UIScreen.mainScreen.bounds;
    double W = window.size.width, H = window.size.height;
    double cx = CGRectGetMidX(icon), cy = CGRectGetMidY(icon), iw = icon.size.width;
    BOOL preserveScaledIconOverlay = CG27PreserveScaledIconOverlay();
    CG27GenieDriver *genie = gCG27Genie;
    // Only a genie that is still moving is retargeted. An open that already settled (iOS 16 keeps its
    // transition in phase 2 for a while, so the driver may still be alive) must not turn the next close
    // into a "retarget": that path ran on wall-clock time and drifted from the window's real crop.
    // The live driver must also still hold the window's current container: SpringBoard can rebuild it between the open
    // and a quick close, and a retargeted driver bound to the old view finished on its next frame (no genie at all).
    UIView *current = genie.container ? [CG27SwitcherVC() _itemContainerForAppLayoutIfExists:appLayout] : nil;
    if (genie && genie.preserveScaledIconOverlay == preserveScaledIconOverlay &&
        genie.appLayout && [genie.appLayout isEqual:appLayout] && genie.link &&
        !G27GenieSettled(&genie->_engine) && (!genie.container || genie.container == current)) {
        // iOS 27 retargets the live vertex springs (retargetImpulse 0) instead of restarting.
        G27GenieRetarget(&genie->_engine, !opening, cx, cy, iw, W, H, response, zeta);
        CG27Event(@"retarget %p to %s b %.3f bv %.3f", genie, opening ? "open" : "close", genie->_engine.b, genie->_engine.bv);
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
    genie.preserveScaledIconOverlay = preserveScaledIconOverlay;
    genie.intensity = CG27Intensity();
    G27GenieStart(&genie->_engine, !opening, cx, cy, iw, W, H, response, zeta);
    genie.iconWidth = iw;
    genie.opening = opening;
    gCG27Genie = genie;
    [genie start];
}

// iOS 16 darkens the badge with a pressed icon (accessory brightness < 1), so it flashed dark red/black as an app
// opened; on iOS 27 the badge of a pressed icon stays red (slow-motion VM frames).
%hook SBIconBadgeView
- (void)setAccessoryBrightness:(CGFloat)brightness {
    %orig(CG27AppEnabled() ? 1.0 : brightness);
}
%end

%hook SBFullScreenToHomeIconZoomSwitcherModifier

- (id)layoutSettingsForTargetCenter:(CGPoint)center {
    id settings = %orig;
    if (!settings || !CG27AppEnabled()) return settings;
    NSUInteger direction = CG27UIntIvar(self, "_direction"); // 0 = home -> app (open), 1 = app -> home
    if (direction > 1) return settings;
    double slow = CG27SlowFactor(), closeScale = direction == 0 ? 1.0 : CG27CloseScale();
    if (direction != 0 && slow == 1.0 && closeScale == 1.0) return settings;
    SBFFluidBehaviorSettings *tuned = [settings copy];
    // Keep the 120 Hz request of the original spring on the copy (see CG27RequestHighFrameRate).
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
    // The droplet also ends on the clock: if the reset timer is dropped (its validator fails on an interrupted or
    // very short transition), the window would otherwise land in the icon as a circle (r = half its side).
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

// The droplet window must start when the animation does. On iOS 16 that is phase 2
// (transitionWillUpdate, implemented by the superclass); phase 1 can last ~80 ms while the app launches.
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
                // iOS 27 genie attributes carry layoutSettings: the zoom spring, or for a swipe-to-home the
                // gesture's layout spring (homeGesture{Top,Bottom}RowZoomDownLayoutSettings, ratio 1.1, response
                // scaled by the lift-off velocity) set by -[SBGestureInitiatedIconZoom… genieAttributesForAppLayout:].
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

// Swipe-to-home: SBHomeGestureToZoomDownSwitcherModifier adds an SBGestureInitiatedIconZoomAnimationAttributes-
// SwitcherModifier (iOS 16 and 27 alike) with its own layout/position/scale springs. iOS 27 additionally hands its
// layout spring to the genie and to the corner radius (decomp/HomeGesture, …genieAttributesForAppLayout: and
// …animationAttributesForLayoutElement:). The springs themselves get iOS 27 values in CG27ApplyIOS27Settings.
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

// iOS 27.0 values of SBFluidSwitcherAnimationSettings that differ from iOS 16.2 (logs/*AnimationSettings*,
// diffed 2026-10-05). Applied after PTSettings sets its defaults, so they stay in effect for the session.
@interface SBFluidSwitcherAnimationSettings : NSObject
@end

// Stock values of everything CG27ApplyIOS27Settings changes, recorded on first change ("key" or "key.property"),
// so switching app animations off in Settings restores iOS 16 without a respring.
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
    // Default: iOS 27's own springs (the small overshoot included). The critically damped variant (GestureBounce =
    // NO) drifted away from 27: the crop lagged the scale and the window squashed in place after landing.
    BOOL on = !v || CFGetTypeID(v) != CFBooleanGetTypeID() || CFBooleanGetValue((CFBooleanRef)v);
    if (v) CFRelease(v);
    return on;
}

static void CG27ApplyIOS27Settings(id s) {
    if (!s || !CG27AppEnabled()) return;
    // Home-gesture zoom springs: no retarget kick, top-row position 0.8 / scale 0.84 damping.
    for (NSString *row in @[@"TopRow", @"BottomRow"])
        for (NSString *kind in @[@"Layout", @"Position", @"Scale"])
            CG27SetSpring(s, [NSString stringWithFormat:@"homeGesture%@ZoomDown%@Settings", row, kind], -1, -1, 0);
    CG27SetSpring(s, @"homeGestureTopRowZoomDownPositionSettings", 0.8, 0.45, 0);
    CG27SetSpring(s, @"homeGestureTopRowZoomDownScaleSettings", 0.84, 0.55, 0);
    // iOS 27's zoom-down position/scale springs are slightly underdamped (0.8-0.86): the icon overshoots ~4 pt
    // up/left and 3% in scale before settling (measured identically on 27 and here). Kept by default (exactly 27);
    // GestureBounce = NO makes them critically damped so the window lands in the icon without the "jelly".
    // A critically damped spring arrives later than the bouncy one, so the responses are shortened too
    // (iOS 27 values x kCG27NoBounceResponseScale) to land in about the same time as 27's first arrival.
    if (!CG27GestureBounce()) {
        CG27SetSpring(s, @"homeGestureTopRowZoomDownPositionSettings", 1.0, 0.45 * kCG27NoBounceResponseScale, 0);
        CG27SetSpring(s, @"homeGestureTopRowZoomDownScaleSettings", 1.0, 0.55 * kCG27NoBounceResponseScale, 0);
        CG27SetSpring(s, @"homeGestureBottomRowZoomDownPositionSettings", 1.0, 0.55 * kCG27NoBounceResponseScale, 0);
        CG27SetSpring(s, @"homeGestureBottomRowZoomDownScaleSettings", 1.0, 0.55 * kCG27NoBounceResponseScale, 0);
    }
    CG27SetSpring(s, @"homeGestureCenterRowZoomUpSettings", -1, -1, 0);
    CG27SetSpring(s, @"homeGestureEdgeRowZoomUpSettings", -1, -1, 0);
    // Home screen fade: critically damped and faster (0.601 / 0.444 on iOS 16).
    CG27SetSpring(s, @"homeScreenOpacitySettings", 1.0, 0.23, -1);
    // The wallpaper no longer zooms behind an open app (1.2 on iOS 16); icons still recede to 0.88.
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

// Finger follow: iOS 27's SBHomeGestureSwitcherModifier reads its minimum card scale from
// homeGestureMinimumCardScale (0.55 in the settings), but on iPhone the live ivar is 0.4, the same constant iOS 16
// hard-codes, and the recorded drag curves (frida/run_follow.py, logs/ios27_follow.log) match iOS 16 to 0.002.
// So the tracking itself is left stock; the differences are the springs below and in CG27ApplyIOS27Settings.

// iOS 27 scales the response of the swipe-to-home zoom springs (layout, position, scale; interpolated by the
// icon's row) by homeGestureZoomDownScaleMultiplier 0.8 on iPhone (0.75 for widgets), so the window settles into
// the icon faster. iOS 16 has no multiplier. The genie uses the same layout spring.

%hook SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier
- (id)_settingsByInterpolatingBetween:(id)a and:(id)b progress:(double)progress {
    SBFFluidBehaviorSettings *settings = %orig;
    if (CG27AppEnabled() && UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone &&
        [settings isKindOfClass:%c(SBFFluidBehaviorSettings)] && settings.response > 0.05)
        settings.response = settings.response * kCG27ZoomDownResponseMultiplier * CG27CloseScale();
    return settings;
}
%end

// ---------------------------------------------------------------------------------------------
// iOS 27 icon fly-in when the cover sheet (Notification Center / Lock Screen) is dismissed over the home
// screen (docs/analysis/ANALYSIS_flyin_unlock_open.md, section 1). iOS 16 only flies icons in on some unlocks,
// all icons on one shared spring; iOS 27 hides the icons while the sheet is dragged, then on commit:
//   - perspective m34 = -1/300 around the screen centre, every icon on its own zPosition spring
//     (response 0.42 + t^3/1.4, t = min(distance from centre / 366 pt, 1); damping 0.731) -> centre icons land
//     first, the corners and the dock last;
//   - icons spread from the centre to their places (S: 0 -> 1, response 0.36, critically damped);
//   - icon container alpha S^2 and gaussian blur 6 * (1 - S).
// Everything is a Core Animation spring/keyframe animation, so it runs in the render server.
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

// iOS 27 SBCoverSheetIconFlyInAnimator (SpringBoard 27.0, IDA; checked live on the 27 VM, logs/ios27_rec_manual.txt):
// fly-in when the cover sheet / Notification Center is dismissed over the home screen, fly-out when it is pulled
// down over it (27 animates both: animateIconsOnPresentationToo; 16 has neither on NC). Both start on release
// (_finishTransitionToPresented -> prepareToAnimateIconFlyInForPresenting:withVelocity:_viewVelocity).
// - icons: perspective m34 = -1/5082.15 (_perspectiveTransform) about the screen centre; zPosition 10000 <-> 0
//   (behind the camera = not drawn), each icon on its own spring: response 0.42 +/- t^3 / 1.4 (fly-in +, fly-out -,
//   t = |icon - C| / 366), damping min(0.82 - 0.22 (v - 3) / 7, 0.82) (v = _velocity: a hard flick is bouncier),
//   initial z velocity -(screen height x v) / 200;
// - spread S (0 = out, 1 = home), critically damped 0.36 (iconsFlyInResponse / iconsFlyOutResponse), initial
//   velocity 2 v (fly-in) / 4 v (fly-out); position = C + (P - C)(1.7 - 0.7 S), C = (W/2, H/2 - 16);
// - icon list blur R (1 - S), R = 6 fly-in / 10 fly-out; list alpha S^2 on fly-out only;
// - dock: dockOffscreenFraction = 4 x base fraction (1 - progress) on spring 0.548 / 0.74 (page control + search
//   pill follow it); the poster wallpaper gets updateWallpaperAnimationWithIconFlyInTension:72 friction:14.4.
static const double kCG27FlyCameraDistance = 5082.15;    // -1 / -0.000196767116
static const double kCG27FlyFarZ = 10000.0;
static const double kCG27FlyMaxDistance = 366.0;         // iPhone (iPad 666)
static const double kCG27FlyZResponse = 0.42, kCG27FlyZCurve = 1.4;
static const double kCG27FlyZDampingMax = 0.82, kCG27FlyZDampingSlope = -0.22 / 7, kCG27FlyZDampingFrom = 3;
static const double kCG27FlySpreadResponse = 0.36, kCG27FlySpreadExtra = 0.7, kCG27FlyCenterLift = 16.0;
static const double kCG27FlyBlurIn = 6.0, kCG27FlyBlurOut = 10.0;
static const double kCG27FlyDockResponse = 0.547826087, kCG27FlyDockDamping = 0.74, kCG27FlyDockOffscreen = 4.0;
static NSString *const kCG27FlyInKey = @"iOS2627AnimsFlyIn";

static BOOL gCG27FlyHidden;          // icon list transparent + dock offscreen (sheet over the home screen)
static BOOL gCG27FlyOutArmed;        // presentation gesture started over the home screen
// The sheet last came to rest presented (not a pull still in progress). SpringBoard starts on the lock screen.
static BOOL gCG27SheetSettledShown = YES;
static NSInteger gCG27FlyGeneration;

// Settings pane tuning of the icon fly. FlyStrength k (1 = iOS 27) scales how far outside their places the icons
// start (0.7 k). With 27's spread spring (0.36 s) the sideways part is over while the icons are still near the
// camera and hugely magnified, so a wider start alone was invisible: above 1 the spread spring slows down with k too
// and the icons visibly converge as they land. 0 = depth only. FlyBlur: the blur that clears as they land.
static double CG27FlyStrength(void) {
    return CG27DoublePref(CFSTR("FlyStrength"), 1.0, 0, 3);
}

static double CG27FlySpreadExtra(void) {
    return kCG27FlySpreadExtra * CG27FlyStrength();
}

static double CG27FlySpreadResponse(void) {
    return kCG27FlySpreadResponse * fmax(1.0, CG27FlyStrength());
}

static BOOL CG27FlyBlurEnabled(void) {
    return CG27BoolPref(CFSTR("FlyBlur"), YES);
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

// Dock: -[SBCoverSheetIconFlyInAnimator _updateDockForFraction:] = super with 4 x fraction on the root folder's
// dockOffscreenFraction modifier (1 = one dock height below).
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

// Re-layout the dock on/off screen without animation, then slide every view the layout moved (dock, page control,
// search pill) with the base fraction spring: the offscreen fraction is linear in position, so an additive spring
// with the same response/damping reproduces 27's animated layout (16 does not animate that layout in a UIKit spring).
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
        if (s0 && s1 && fabs((s0.doubleValue - s1.doubleValue) - d) < 0.5) continue;   // moved with its parent
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

// Icon lists a fly or hide changed, each with its own sublayerTransform from before the first fly (associated object).
// The current page can change between hiding and showing (Today view, App Library, another page after an unlock), and a
// newer generation cancels the previous fly's cleanup; both used to leave a page transparent or blurred, so a later app
// close zoomed into invisible icons.
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

// Back to the list as it was before any fly: transform, filters, opacity and leftover icon animations.
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

// Pages other than the current one are off screen: visible again, and forgotten.
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
    dock.layer.opacity = (hidden && !moved) ? 0 : 1;   // fallback without the modifier: hide the dock instead
}

// Time at which a unit spring 1 -> 0 (from rest) first drops below `level`.
static double CG27FlyCrossing(double response, double damping, double level) {
    double x = 1, v = 0, t = 0, dt = 1.0 / 480;
    while (x > level && t < 3) { G27SpringStep(&x, &v, 0, response, damping, dt); t += dt; }
    return t;
}

// Widgets and folders draw their background with a backdrop material that samples the wallpaper. Under a filter
// on an ancestor the backdrop sees only the filtered group (not the wallpaper) and the material changes tone, so
// such icons are left out of the blur.
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

// flyIn: S 0 -> 1, icons from behind the camera into place. !flyIn: S 1 -> 0, icons out through the camera.
static void CG27FlyRun(BOOL flyIn, double velocity) {
    // The fly's own Core Animation springs do not see UIKit's drag coefficient: slow them by the same factor.
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
    double spreadVelocity = (flyIn ? 2 : 4) * v;             // dS/dt at the start (S rises on fly-in, falls on fly-out)
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
        // A fly started while another is in flight must not save the perspective it finds as the "original".
        CG27FlyTouch(list);
        L.filters = nil;
        BOOL backdrops = NO;
        for (UIView *iv in list.subviews)
            if ([iv isKindOfClass:%c(SBIconView)] && !iv.hidden && CG27FlyIconHasBackdrop(iv)) { backdrops = YES; break; }
        // Perspective about the screen centre: T(-d) * P * T(d), d = centre - layer anchor (list coordinates).
        CGPoint c = [list convertPoint:screenCenter fromView:nil];
        CGPoint anchor = CGPointMake(CGRectGetMidX(list.bounds), CGRectGetMidY(list.bounds));
        CATransform3D P = CATransform3DIdentity;
        P.m34 = -1.0 / kCG27FlyCameraDistance;
        L.sublayerTransform = CATransform3DConcat(CATransform3DConcat(
            CATransform3DMakeTranslation(-(c.x - anchor.x), -(c.y - anchor.y), 0), P),
            CATransform3DMakeTranslation(c.x - anchor.x, c.y - anchor.y, 0));
        L.opacity = flyIn ? 1 : 0;

        // Spread S sampled at 60 Hz: list blur R (1 - S), and alpha S^2 on fly-out.
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
        // One blur on the whole list, or, with widgets/folders on the page, one per plain icon (see above).
        CAFilter *blur = CG27FlyBlurEnabled() ? [%c(CAFilter) filterWithType:@"gaussianBlur"] : nil;
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
        double visibleZ = kCG27FlyCameraDistance * 0.98 / kCG27FlyFarZ;   // fraction of the far z still drawn
        for (UIView *iv in list.subviews) {
            if (![iv isKindOfClass:%c(SBIconView)] || iv.hidden) continue;
            CALayer *I = iv.layer;
            [I removeAnimationForKey:kCG27FlyInKey];
            CGPoint p = I.position, pw = [list convertPoint:p toView:nil];
            double t = fmin(hypot(pw.x - spreadCenterW.x, pw.y - spreadCenterW.y) / kCG27FlyMaxDistance, 1.0);
            double k = t * t * t / kCG27FlyZCurve;
            // Fly-out: 0.42 - k can go negative; tension (2 pi / r)^2 and friction 2 zeta sqrt(tension) make it |r|.
            double response = fmax(fabs(flyIn ? kCG27FlyZResponse + k : kCG27FlyZResponse - k), 0.02);
            CGPoint out = CGPointMake(C.x + (p.x - C.x) * m, C.y + (p.y - C.y) * m);
            // Children of a group run in the group's local time: they start at 0, the group at `begin`.
            CASpringAnimation *z = CG27FlySpring(@"zPosition", @(I.zPosition + zFrom), @(I.zPosition + zTo), response, zDamping,
                                                 zVelocity / (zTo - zFrom));
            CASpringAnimation *spread = CG27FlySpring(@"position", [NSValue valueWithCGPoint:flyIn ? out : p],
                                                      [NSValue valueWithCGPoint:flyIn ? p : out], spreadResponse, 1.0, towardSpread);
            // Behind the camera (z > d) 27 draws nothing: transparent while z is beyond the camera.
            double cross = CG27FlyCrossing(response, zDamping, flyIn ? visibleZ : 1 - visibleZ);
            CAKeyframeAnimation *show = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            // Discrete keyframes need one more key time than values.
            show.values = flyIn ? @[@0, @1] : @[@1, @0];
            show.keyTimes = @[@0, @(fmin(cross / z.duration, 1)), @1];
            show.calculationMode = kCAAnimationDiscrete;
            show.duration = z.duration;
            // A filter crops its layer to the bounds, and the badge (SBIconBadgeView inside SBIconImageView at
            // x 49, y -11 on a 64 pt icon) sticks out of every ancestor: badged icons are not blurred.
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

// Cover sheet look, decoded from CoverSheet.framework 16.2 and 27.0 (-[CSCoverSheetTransitionsSettings
// setDefaultValues...], IDA): both share the base values, but 16 finishes with setDefaultValuesForParallaxAndBlur
// and 27 with the new setDefaultValuesForCrossFadeOnTouchUp. Over the home screen 27 turns every panel effect off:
// no lock wallpaper copy on the panel, no panel blur, no darkening, no fading wallpaper copy (fadesContent, the haze
// over the icons near the top), no floating wallpaper layer, no tracking/scaled wallpaper; the icons stay visible
// under the sheet (27 then cross-blurs the two wallpapers, crossBlursForTransition, which 16 does not have). Over an
// app it keeps the panel wallpaper but without blur or content fade, moving with the panel (tracking, parallax 0).
// Key ClearSheet (default YES, needs IconFlyIn). The values are written into the transition settings children the
// first time they are read after a change; switching off restores 16 with -setDefaultValues.
static NSString *const kCG27SheetKeys[] = {
    @"sameWallpaperInitialTransitionSettings", @"sameWallpaperSubsequentTransitionSettings",
    @"differentWallpaperInitialTransitionSettings", @"differentWallpaperSubsequentTransitionSettings",
    @"overAppTransitionSettings",
};
static const void *kCG27SheetModeKey = &kCG27SheetModeKey;
static BOOL gCG27SheetBusy;

static BOOL CG27Sheet27Enabled(void) {
    return CG27FlyInEnabled() && CG27BoolPref(CFSTR("ClearSheet"), YES);
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
        // 27 leaves the initial same-wallpaper sheet's floating layer as the base configuration sets it (YES).
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

// The built-in iOS 16 fly-in (some unlocks) would run on top of ours.
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
    // A released half-way pull reverses into a dismissal: the icons never flew out, so they stay (27 alternates
    // fly-out / fly-in through iconsWereLastAnimatedIn, and does not touch the icons at all while a finger drags the
    // sheet). iOS 16 does not always report such a pull as `reversing`, so also keep them unless the sheet had come to
    // rest presented (lock screen, or a Notification Center that never flew the icons out): only then hide them for
    // the fly-in.
    if (!gCG27FlyHidden && (reversing || !gCG27SheetSettledShown)) return;
    if (CG27FlyHomeVisible()) { if (!gCG27FlyHidden) CG27FlySetHidden(YES); }
    else if (gCG27FlyHidden) CG27FlySetHidden(NO);
}

- (void)coverSheetSlidingViewController:(id)controller committingToEndPresented:(BOOL)presented {
    %orig;
    BOOL armed = gCG27FlyOutArmed;
    gCG27FlyOutArmed = NO;
    if (!presented && !gCG27FlyHidden) return;
    if (presented && !armed) return;   // e.g. a cancelled dismissal: icons stay as they are under the sheet
    // -[SBCoverSheetSlidingViewController _finishTransitionToPresented:...] passes -[... _viewVelocity] (-finger dy/dt
    // / sheet height, clamped to +-10; same in 16) to prepareToAnimateIconFlyInForPresenting:withVelocity:.
    SEL vsel = NSSelectorFromString(@"_viewVelocity");
    double velocity = [controller respondsToSelector:vsel] ? ((double (*)(id, SEL))objc_msgSend)(controller, vsel) : 0;
#if CG27_TEST_HOOKS
    NSLog(@"[iOS2627Anims] fly %s velocity %.3f", presented ? "out" : "in", velocity);
#endif
    if (!CG27FlyInEnabled() || !CG27FlyHomeVisible()) { if (gCG27FlyHidden) CG27FlySetHidden(NO); return; }
    CG27FlyRun(!presented, velocity);
}

// Safety net: once the sheet has settled, icons stay hidden only while it covers the home screen.
- (void)coverSheetSlidingViewControllerDidEndTransition:(id)controller {
    %orig;
    id manager = (id)self;
    BOOL presented = [manager respondsToSelector:@selector(isPresented)] && ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isPresented));
    gCG27SheetSettledShown = presented;
    if (gCG27FlyHidden && (!presented || !CG27FlyHomeVisible())) CG27FlySetHidden(NO);
}
%end

%hook SBFluidSwitcherViewController

- (id)_itemContainerForAppLayoutIfExists:(id)appLayout {
    gCG27SwitcherVC = self;
    return %orig;
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

// Posted by the Settings pane (iOS2627AnimsPrefs) after any switch changes: re-read the domain and rebuild the
// switcher springs from their stock values (iOS 27 values are added back only while app animations are on).
static NSString *const kCG27PrefsChanged = @"com.bazik1337.ios2627anims/changed";

static void CG27PrefsChanged(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name,
                             __unused const void *object, __unused CFDictionaryRef info) {
    CFPreferencesAppSynchronize(CFSTR("com.bazik1337.ios2627anims"));
    dispatch_async(dispatch_get_main_queue(), ^{
        gCG27PrefsLoaded = -1;
        gCG27GlobalSlow = CG27DoublePref(CFSTR("GlobalSlow"), 1.0, 1.0, 10.0);
        id animation = CG27AnimationSettings();
        CG27RestoreStockSettings(animation);
        CG27ApplyIOS27Settings(animation);
        if (!CG27FlyInEnabled() && gCG27FlyHidden) CG27FlySetHidden(NO);
    });
}

%hookf(float, UIAnimationDragCoefficient) {
    float drag = %orig;
    double k = gCG27GlobalSlow;
    return k > 1.001 ? (float)(drag * k) : drag;
}

%ctor {
    %init;
    gCG27GlobalSlow = CG27DoublePref(CFSTR("GlobalSlow"), 1.0, 1.0, 10.0);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CG27PrefsChanged,
                                    (__bridge CFStringRef)kCG27PrefsChanged, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    // Settings may already exist when we load: apply once more on the next run-loop turn.
    dispatch_async(dispatch_get_main_queue(), ^{
        CG27ApplyIOS27Settings(CG27AnimationSettings());
    });
}

#if CG27_TEST_HOOKS
// ---------------------------------------------------------------------------------------------
// Test hooks (debug builds only; FINALPACKAGE=1 leaves them out). Frida calls these exported functions on the main
// queue to drive real transitions: SpringBoard's own RecapPerformanceTesting swipes and icon taps.
@interface RCPSyntheticEventStream : NSObject
+ (id)eventStreamWithEventActions:(void (^)(id composer))actions;
@end
@interface RCPInlinePlayer : NSObject
- (void)playEventStream:(id)stream options:(id)options completion:(void (^)(void))completion;
@end
@interface SpringBoard : UIApplication
- (id)_flickTimingFunction;
- (void)_performSwipeWithComposer:(id)composer startLocation:(CGPoint)start endLocation:(CGPoint)end duration:(double)duration
                   timingFunction:(id)timing intermediateTransformer:(CGPoint (^)(CGPoint))transformer completion:(void (^)(void))completion;
@end
@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
@end
@interface SBIconView : UIView
- (id)icon;
- (void)performTap;
@end

static RCPInlinePlayer *gCG27TestPlayer;

__attribute__((visibility("default"))) void CG27TestSwipe(const double *xy, int count, double duration) {
    if (count < 2 || !xy) return;
    NSMutableArray *pts = [NSMutableArray array];
    for (int i = 0; i < count; i++) [pts addObject:[NSValue valueWithCGPoint:CGPointMake(xy[2 * i], xy[2 * i + 1])]];
    CGPoint start = [pts.firstObject CGPointValue], end = [pts.lastObject CGPointValue];
    double dx = end.x - start.x, dy = end.y - start.y, len2 = dx * dx + dy * dy;
    CGPoint (^transformer)(CGPoint) = count <= 2 ? nil : ^CGPoint(CGPoint p) {
        double u = fmax(0, fmin(1, ((p.x - start.x) * dx + (p.y - start.y) * dy) / len2));
        double f = u * (count - 1); int i = MIN(count - 2, (int)floor(f)); double r = f - i;
        CGPoint a = [pts[i] CGPointValue], b = [pts[i + 1] CGPointValue];
        return CGPointMake(a.x + (b.x - a.x) * r, a.y + (b.y - a.y) * r);
    };
    SpringBoard *sb = (SpringBoard *)UIApplication.sharedApplication;
    Class streamClass = NSClassFromString(@"RCPSyntheticEventStream"), playerClass = NSClassFromString(@"RCPInlinePlayer");
    if (!streamClass || !playerClass || ![sb respondsToSelector:@selector(_flickTimingFunction)]) return;
    id stream = [streamClass eventStreamWithEventActions:^(id composer) {
        [sb _performSwipeWithComposer:composer startLocation:start endLocation:end duration:duration
                       timingFunction:[sb _flickTimingFunction] intermediateTransformer:transformer completion:nil];
    }];
    gCG27TestPlayer = [playerClass new];
    [gCG27TestPlayer playEventStream:stream options:nil completion:^{}];
}

static SBIconView *CG27FindIconView(UIView *view, NSString *bundle) {
    if ([view isKindOfClass:%c(SBIconView)] && !view.hidden && view.window) {
        id icon = [(SBIconView *)view icon];
        if ([icon respondsToSelector:@selector(applicationBundleID)] && [[icon applicationBundleID] isEqual:bundle]) {
            CGRect r = [view convertRect:view.bounds toView:nil];
            if (r.origin.x > -1 && r.origin.x < view.window.bounds.size.width) return (SBIconView *)view;
        }
    }
    for (UIView *sub in view.subviews) { SBIconView *found = CG27FindIconView(sub, bundle); if (found) return found; }
    return nil;
}

__attribute__((visibility("default"))) int CG27TestOpen(const char *bundleID) {
    NSString *bundle = @(bundleID);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray *windows = UIApplication.sharedApplication.windows;
#pragma clang diagnostic pop
    for (UIWindow *w in windows) {
        if (![NSStringFromClass(w.class) containsString:@"HomeScreen"]) continue;
        SBIconView *view = CG27FindIconView(w, bundle);
        if (view) { [view performTap]; return 1; }
    }
    return 0;
}

// Native recorder for tests: samples the genie's item container + engine every frame into a C buffer.
#define CG27_REC_STRIDE 32
#define CG27_REC_MAX 1200
static double gCG27Rec[CG27_REC_MAX * CG27_REC_STRIDE];
static int gCG27RecCount;
static __weak UIView *gCG27RecContainer;
static CADisplayLink *gCG27RecLink;
static double gCG27RecT0;

@interface CG27Recorder : NSObject
@end
@implementation CG27Recorder
+ (void)tick:(CADisplayLink *)link {
    if (gCG27RecCount >= CG27_REC_MAX) return;
    CG27GenieDriver *drv = gCG27Genie;
    UIView *c = drv.container ?: gCG27RecContainer;
    if (drv.container) gCG27RecContainer = drv.container;
    if (!c) return;
    CALayer *p = c.layer.presentationLayer ?: c.layer;
    double *r = &gCG27Rec[gCG27RecCount++ * CG27_REC_STRIDE];
    memset(r, 0, sizeof(double) * CG27_REC_STRIDE);
    r[0] = CACurrentMediaTime() - gCG27RecT0;
    r[1] = p.position.x; r[2] = p.position.y; r[3] = p.bounds.size.width; r[4] = p.bounds.size.height;
    r[5] = [[p valueForKeyPath:@"transform.scale.x"] doubleValue];
    if (drv && drv.container == c) {
        G27Genie *g = &drv->_engine;
        r[6] = 1; r[7] = g->b; r[8] = g->bTarget; r[9] = g->bResponse; r[10] = g->zeta; r[11] = g->px; r[12] = g->ms;
        for (int k = 0; k < G27_V; k++) { r[13 + 2 * k] = g->p[k][0]; r[14 + 2 * k] = g->p[k][1]; }
        r[31] = drv.renderedB;
    }
}
@end

__attribute__((visibility("default"))) void CG27TestRecord(int on) {
    [gCG27RecLink invalidate]; gCG27RecLink = nil;
    if (!on) return;
    gCG27RecCount = 0; gCG27RecT0 = CACurrentMediaTime(); gCG27RecContainer = nil;
    gCG27RecLink = [CADisplayLink displayLinkWithTarget:[CG27Recorder class] selector:@selector(tick:)];
    CG27RequestHighFrameRate(gCG27RecLink, kCG27DefaultFrameRateReason);
    [gCG27RecLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

__attribute__((visibility("default"))) const char *CG27TestEvents(int clear) {
    static char buf[16384];
    snprintf(buf, sizeof(buf), "%s", gCG27Events.UTF8String ?: "");
    if (clear) gCG27Events = nil;
    return buf;
}

__attribute__((visibility("default"))) int CG27TestDump(double *out, int max) {
    int n = MIN(max, gCG27RecCount);
    memcpy(out, gCG27Rec, sizeof(double) * CG27_REC_STRIDE * n);
    return n;
}

// Screen frames for visual comparison with iOS 27. Only the snapshot itself runs on the main thread (from a
// display link); scaling to 1/3 and JPEG encoding happen on a background queue, at most 8 frames in flight.
#import <ImageIO/ImageIO.h>
extern UIImage *_UICreateScreenUIImage(void) NS_RETURNS_RETAINED; // +1 ("Create")

@interface CG27Shooter : NSObject
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, copy) NSString *folder;
@property (nonatomic) int left, index;
@property (nonatomic) double t0, mainCost, delay;
@end
static CG27Shooter *gCG27Shooter;
static dispatch_queue_t gCG27ShotQueue;
static volatile int gCG27ShotPending;

@implementation CG27Shooter
- (void)tick:(CADisplayLink *)link {
    if (self.left-- <= 0) { [self.link invalidate]; self.link = nil; return; }
    if (CACurrentMediaTime() - self.t0 < self.delay) return;
    if (gCG27ShotPending >= 8) return; // ~14 MB per full-size frame: cap the backlog (jetsam)
    double start = CACurrentMediaTime();
    UIImage *image = _UICreateScreenUIImage();
    self.mainCost += CACurrentMediaTime() - start;
    CGImageRef cg = image.CGImage;
    if (!cg) return;
    CGImageRetain(cg);
    NSString *path = [self.folder stringByAppendingPathComponent:
        [NSString stringWithFormat:@"c%03d_%.3f.jpg", self.index++, start - self.t0]];
    __sync_fetch_and_add(&gCG27ShotPending, 1);
    dispatch_async(gCG27ShotQueue, ^{
        size_t w = CGImageGetWidth(cg) / 3, h = CGImageGetHeight(cg) / 3;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef small = CGBitmapContextCreate(NULL, w, h, 8, 0, space, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        CGContextSetInterpolationQuality(small, kCGInterpolationNone);
        CGContextDrawImage(small, CGRectMake(0, 0, w, h), cg);
        CGImageRelease(cg);
        CGImageRef out = CGBitmapContextCreateImage(small);
        CGContextRelease(small); CGColorSpaceRelease(space);
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                                                     CFSTR("public.jpeg"), 1, NULL);
        if (dest) {
            CGImageDestinationAddImage(dest, out, (__bridge CFDictionaryRef)@{(id)kCGImageDestinationLossyCompressionQuality: @0.75});
            CGImageDestinationFinalize(dest); CFRelease(dest);
        }
        CGImageRelease(out);
        __sync_fetch_and_sub(&gCG27ShotPending, 1);
    });
}
@end

__attribute__((visibility("default"))) double CG27TestShots(const char *dir, int count, int fps, double delay) {
    CG27Shooter *old = gCG27Shooter;
    double cost = old.index ? old.mainCost / old.index : 0; // mean main-thread cost of the previous run
    [old.link invalidate]; gCG27Shooter = nil;
    if (count <= 0 || !dir) return cost;
    if (!gCG27ShotQueue) gCG27ShotQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    CG27Shooter *shooter = [CG27Shooter new];
    shooter.folder = @(dir); shooter.left = count; shooter.t0 = CACurrentMediaTime(); shooter.delay = delay;
    [[NSFileManager defaultManager] createDirectoryAtPath:shooter.folder withIntermediateDirectories:YES attributes:nil error:nil];
    shooter.link = [CADisplayLink displayLinkWithTarget:shooter selector:@selector(tick:)];
    if (@available(iOS 15.0, *)) shooter.link.preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
    [shooter.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    gCG27Shooter = shooter;
    return cost;
}
#endif // CG27_TEST_HOOKS
