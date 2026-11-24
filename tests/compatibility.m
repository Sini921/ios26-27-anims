#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <assert.h>

static unsigned installed;
static void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls, selector);
    assert(method);
    *original = method_getImplementation(method);
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    installed++;
}

#define CG27_TESTING 1
#include "../shared/HookCompatibility.h"
#include "../shared/AfterLaunch.h"

@interface CG27TestParent : NSObject
- (id)transitionWillBegin;
@end
@implementation CG27TestParent
- (id)transitionWillBegin { return @"stock"; }
@end
@interface CG27TestChild : CG27TestParent
@end
@implementation CG27TestChild
@end

static id (*originalBegin)(id, SEL);
static id hookedBegin(id self, SEL selector) {
    return [originalBegin(self, selector) stringByAppendingString:@"+hook"];
}
static void unusedHook(__unused id self, __unused SEL selector) { assert(!"unexpected hook call"); }
static float stockFloat(__unused id self, __unused SEL selector) { return 3.5f; }
static CG27CornerRadii stockRadii(__unused id self, __unused SEL selector, NSUInteger index) {
    return (CG27CornerRadii){index, 2, 3, 4};
}
static CG27CornerRadii (*originalRadii)(id, SEL, NSUInteger);
static CG27CornerRadii hookedRadii(id self, SEL selector, NSUInteger index) {
    CG27CornerRadii result = originalRadii(self, selector, index);
    result.topLeft += 1;
    return result;
}

int main(void) {
    @autoreleasepool {
        IMP original = NULL;
        SEL missing = sel_registerName("coverSheetSlidingViewControllerDidEndTransition:");
        CG27HookMessageEx(CG27TestChild.class, missing, (IMP)unusedHook, &original);
        assert(!class_getInstanceMethod(CG27TestChild.class, missing));
        assert(!original && installed == 0);
        CG27HookMessageEx(Nil, missing, (IMP)unusedHook, &original);
        assert(installed == 0);

        CG27HookMessageEx(CG27TestChild.class, @selector(transitionWillBegin), (IMP)hookedBegin, (IMP *)&originalBegin);
        assert(installed == 1);
        assert([[[CG27TestChild new] transitionWillBegin] isEqual:@"stock+hook"]);
        assert([[[CG27TestParent new] transitionWillBegin] isEqual:@"stock"]);

        Class floatClass = objc_allocateClassPair(NSObject.class, "CG27FloatABI", 0);
        SEL listMinY = sel_registerName("listMinY");
        class_addMethod(floatClass, listMinY, (IMP)stockFloat, "f16@0:8");
        objc_registerClassPair(floatClass);
        CG27HookMessageEx(floatClass, listMinY, (IMP)unusedHook, &original);
        assert(installed == 1 && original == NULL);
        assert(((float (*)(id, SEL))objc_msgSend)([floatClass new], listMinY) == 3.5f);

        Class radiiClass = objc_allocateClassPair(NSObject.class, "CG27NamedStructABI", 0);
        SEL radii = sel_registerName("cornerRadiiForIndex:");
        class_addMethod(radiiClass, radii, (IMP)stockRadii, "{UIRectCornerRadii=dddd}24@0:8Q16");
        objc_registerClassPair(radiiClass);
        CG27HookMessageEx(radiiClass, radii, (IMP)hookedRadii, (IMP *)&originalRadii);
        assert(installed == 2);
        CG27CornerRadii result = ((CG27CornerRadii (*)(id, SEL, NSUInteger))objc_msgSend)([radiiClass new], radii, 7);
        assert(result.topLeft == 8 && result.bottomLeft == 2 && result.bottomRight == 3 && result.topRight == 4);

        // Equal-sized structs can have different register layouts: compare
        // their fields as well as their total sizes.
        Class wrongStruct = objc_allocateClassPair(NSObject.class, "CG27WrongStructABI", 0);
        class_addMethod(wrongStruct, radii, (IMP)unusedHook, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16");
        objc_registerClassPair(wrongStruct);
        CG27HookMessageEx(wrongStruct, radii, (IMP)hookedRadii, &original);
        assert(installed == 2 && original == NULL);

        Class blockClass = objc_allocateClassPair(NSObject.class, "CG27BlockABI", 0);
        SEL catchup = sel_registerName("_startCatchupAnimationWithDuration:completion:");
        class_addMethod(blockClass, catchup, (IMP)unusedHook, "v32@0:8d16@?24");
        objc_registerClassPair(blockClass);
        assert(CG27MethodMatches(class_getInstanceMethod(blockClass, catchup), CG27SignatureForSelector(catchup)));

        __block unsigned launches = 0;
        CG27AfterLaunch(^{ assert(NSThread.isMainThread); launches++; });
        assert(launches == 0);
        CG27AfterLaunch(^{ assert(!"launch action ran twice"); });
        assert(launches == 0);
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        assert(launches == 1);
        puts("PASS: missing hooks, inherited originals, scalar/struct ABI, block arguments, deferred one-shot startup");
    }
    return 0;
}
