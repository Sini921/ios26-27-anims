// Settings pane of iOS 27 Animations. Switches and sliders write the com.bazik1337.ios2627anims domain and post
// com.bazik1337.ios2627anims/changed (Root.plist); SpringBoard applies them without a respring.

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#include <spawn.h>
#include <unistd.h>

static NSString *const kCG27Domain = @"com.bazik1337.ios2627anims";

@interface CG27RootListController : PSListController
@end

@implementation CG27RootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

// Removes every key of the domain (the ones on this page and any left from older versions), so each switch and
// slider falls back to its iOS 27 default, then tells SpringBoard and redraws the page.
- (void)resetSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Вернуть по умолчанию?"
        message:@"Все переключатели и ползунки твика вернутся к значениям iOS 27." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Сбросить" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self performReset];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performReset {
    CFStringRef domain = (__bridge CFStringRef)kCG27Domain;
    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    for (PSSpecifier *spec in self.specifiers) {
        NSString *key = [spec propertyForKey:@"key"];
        if (key.length) [keys addObject:key];
    }
    CFArrayRef stored = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (stored) {
        [keys addObjectsFromArray:(__bridge NSArray *)stored];
        CFRelease(stored);
    }
    for (NSString *key in keys) CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
    CFPreferencesAppSynchronize(domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.bazik1337.ios2627anims/changed"), NULL, NULL, YES);
    [self reloadSpecifiers];
}

- (void)respring {
    // Rootless (Dopamine) first, then rootful.
    for (NSString *tool in @[@"/var/jb/usr/bin/sbreload", @"/usr/bin/sbreload", @"/var/jb/usr/bin/killall", @"/usr/bin/killall"]) {
        if (access(tool.fileSystemRepresentation, X_OK) != 0) continue;
        BOOL killall = [tool hasSuffix:@"killall"];
        const char *argv[] = {tool.fileSystemRepresentation, killall ? "SpringBoard" : NULL, NULL};
        pid_t pid;
        if (posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, NULL) == 0) return;
    }
}

- (void)openChannel {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://t.me/ba31k_tweaks"] options:@{} completionHandler:nil];
}

@end
