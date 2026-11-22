#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#include <spawn.h>
#include <unistd.h>

static NSString *const kCG27Domain = @"com.bazik1337.ios27animsreborn";
static NSString *const kCG27Telegram = @"https://t.me/bazik1337";
static NSString *const kCG27Channel = @"https://t.me/ba31k_tweaks";
static NSString *const kCG27GitHub = @"https://github.com/ba31k/ios26-27-anims";

@interface PSListController (CG27)
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target bundle:(NSBundle *)bundle;
@end

static NSString *CG27L(NSString *key) {
    return [[NSBundle bundleWithIdentifier:@"com.bazik1337.ios27animsreborn.prefs"] localizedStringForKey:key value:key table:@"Root"];
}

static UIColor *CG27Tint(void) {
    return [UIColor colorWithRed:49.0 / 255 green:89.0 / 255 blue:217.0 / 255 alpha:1];
}

static UIImage *CG27Icon(NSString *symbol, UIColor *color) {
    UIImage *glyph = [UIImage systemImageNamed:symbol
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]];
    if (!glyph) return nil;
    CGSize size = CGSizeMake(29, 29);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:6.5] fill];
        UIImage *white = [glyph imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize g = white.size;
        [white drawInRect:CGRectMake((size.width - g.width) / 2, (size.height - g.height) / 2, g.width, g.height)];
    }];
}

static NSArray *CG27Prepare(NSArray *specifiers) {
    NSString *version = [NSBundle bundleWithIdentifier:@"com.bazik1337.ios27animsreborn.prefs"]
        .infoDictionary[@"CFBundleShortVersionString"] ?: @"";
    for (PSSpecifier *spec in specifiers) {
        NSString *symbol = [spec propertyForKey:@"iconSymbol"];
        if (symbol) [spec setProperty:CG27Icon(symbol, CG27Tint()) forKey:@"iconImage"];
        if ([[spec propertyForKey:@"footerText"] isEqual:@"version"])
            [spec setProperty:[NSString stringWithFormat:@"iOS 27 Animations Reborn %@", version] forKey:@"footerText"];
    }
    return specifiers;
}

@interface CG27RebornPageController : PSListController
@end

@implementation CG27RebornPageController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *plist = [self.specifier propertyForKey:@"plist"] ?: @"Root";
        _specifiers = [CG27Prepare([self loadSpecifiersFromPlistName:plist target:self
                                                             bundle:[NSBundle bundleForClass:self.class]]) mutableCopy];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = CG27Tint();
    [UISwitch appearanceWhenContainedInInstancesOfClasses:@[self.class]].onTintColor = CG27Tint();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.tintColor = CG27Tint();
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBar.tintColor = nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [cell respondsToSelector:@selector(specifier)] ? [(id)cell specifier] : nil;
    if ([spec propertyForKey:@"action"]) cell.textLabel.textColor = CG27Tint();
    return cell;
}

@end

@interface CG27RebornRootListController : CG27RebornPageController
@end

@implementation CG27RebornRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 104)];
    UILabel *title = [UILabel new], *subtitle = [UILabel new];
    title.text = @"iOS 27 Animations Reborn";
    title.font = [UIFont systemFontOfSize:25 weight:UIFontWeightBold];
    subtitle.text = @"by bazik1337";
    subtitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    subtitle.textColor = UIColor.secondaryLabelColor;
    for (UILabel *label in @[title, subtitle]) {
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:label];
        [label.centerXAnchor constraintEqualToAnchor:header.centerXAnchor].active = YES;
    }
    [title.topAnchor constraintEqualToAnchor:header.topAnchor constant:28].active = YES;
    [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4].active = YES;
    self.table.tableHeaderView = header;
}

- (void)resetSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CG27L(@"Restore recommended settings?")
        message:CG27L(@"Restore the recommended options and keep the tweak enabled state.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CG27L(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:CG27L(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self performReset];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performReset {
    CFStringRef domain = (__bridge CFStringRef)kCG27Domain;
    CFArrayRef stored = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (stored) {
        for (NSString *key in (__bridge NSArray *)stored)
            if (![key isEqualToString:@"Enabled"] && ![key isEqualToString:@"PromptStage"]) CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
        CFRelease(stored);
    }
    CFPreferencesAppSynchronize(domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.bazik1337.ios27animsreborn/changed"), NULL, NULL, YES);
    [self reloadSpecifiers];
}

@end

@interface CG27RebornAboutController : CG27RebornPageController
@end

@implementation CG27RebornAboutController

- (void)respring {
    for (NSString *tool in @[@"/var/jb/usr/bin/sbreload", @"/usr/bin/sbreload", @"/var/jb/usr/bin/killall", @"/usr/bin/killall"]) {
        if (access(tool.fileSystemRepresentation, X_OK) != 0) continue;
        BOOL killall = [tool hasSuffix:@"killall"];
        const char *argv[] = {tool.fileSystemRepresentation, killall ? "SpringBoard" : NULL, NULL};
        pid_t pid;
        if (posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, NULL) == 0) return;
    }
}

- (void)open:(NSString *)url {
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
}

- (void)openTelegram { [self open:kCG27Telegram]; }
- (void)openChannel { [self open:kCG27Channel]; }
- (void)openGitHub { [self open:kCG27GitHub]; }

@end
