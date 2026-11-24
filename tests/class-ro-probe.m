// Device regression probe: build an arm64e dylib with/without
// -fno-ptrauth-objc-class-ro, then dlopen it in a separate process on iOS 15.
// On the tested iPhone 13 Pro Max / 15.0.2, the default clang output crashed
// in libobjc before constructors; the compatibility build loaded successfully.
#import <Foundation/Foundation.h>
#include <stdio.h>

@interface CG27ClassROProbe : NSObject
@end
@implementation CG27ClassROProbe
@end

__attribute__((constructor)) static void probe(void) {
    fputs("CG27 class_ro probe loaded\n", stderr);
}
