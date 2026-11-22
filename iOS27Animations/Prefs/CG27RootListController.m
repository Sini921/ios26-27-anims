#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#include <spawn.h>
#include <unistd.h>

static NSString *const kCG27Domain = @"com.bazik1337.ios2627anims";
static NSString *const kCG27Telegram = @"https://t.me/bazik1337";
static NSString *const kCG27Channel = @"https://t.me/ba31k_tweaks";
static NSString *const kCG27GitHub = @"https://github.com/ba31k/ios26-27-anims";

@interface PSListController (CG27)
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target bundle:(NSBundle *)bundle;
@end

static NSString *CG27L(NSString *key) {
    return [[NSBundle bundleWithIdentifier:@"com.bazik1337.ios2627anims.prefs"] localizedStringForKey:key value:key table:@"Root"];
}

static UIColor *CG27Tint(void) {
    return [UIColor colorWithRed:0.40 green:0.35 blue:0.98 alpha:1];
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
    NSString *version = [NSBundle bundleWithIdentifier:@"com.bazik1337.ios2627anims.prefs"]
        .infoDictionary[@"CFBundleShortVersionString"] ?: @"";
    for (PSSpecifier *spec in specifiers) {
        NSString *symbol = [spec propertyForKey:@"iconSymbol"];
        if (symbol) [spec setProperty:CG27Icon(symbol, CG27Tint()) forKey:@"iconImage"];
        if ([[spec propertyForKey:@"footerText"] isEqual:@"version"])
            [spec setProperty:[NSString stringWithFormat:@"iOS 27 Animations %@\n%@", version,
                CG27L(@"If you like the tweak, star it on GitHub and join the Telegram channel.")] forKey:@"footerText"];
    }
    return specifiers;
}

@interface CG27PageController : PSListController
@end

@implementation CG27PageController

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

@interface CG27RootListController : CG27PageController
@end

@implementation CG27RootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 104)];
    UILabel *title = [UILabel new], *subtitle = [UILabel new];
    title.text = @"iOS 27 Animations";
    title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
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
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(showPrompt)
                                               name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self showPrompt];
}

- (void)showPrompt {
    if (self.presentedViewController || !self.view.window) return;
    CFStringRef domain = (__bridge CFStringRef)kCG27Domain;
    NSInteger stage = [(__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("PromptStage"), domain) integerValue];
    if (stage >= 2) return;
    BOOL github = stage == 0;
    NSString *title = github ? CG27L(@"Star on GitHub") : CG27L(@"Telegram channel");
    NSString *message = github ? CG27L(@"If you like the tweak, a star on GitHub helps a lot.")
                               : CG27L(@"Updates and new tweaks are posted in the Telegram channel.");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    void (^advance)(void) = ^{
        CFPreferencesSetAppValue(CFSTR("PromptStage"), (__bridge CFNumberRef)@(stage + 1), domain);
        CFPreferencesAppSynchronize(domain);
    };
    [alert addAction:[UIAlertAction actionWithTitle:CG27L(@"Later") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *a) {
        advance();
        if (github) dispatch_async(dispatch_get_main_queue(), ^{ [self showPrompt]; });
    }]];
    UIAlertAction *open = [UIAlertAction actionWithTitle:github ? CG27L(@"Open GitHub") : CG27L(@"Open channel")
                                                   style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        advance();
        [self open:github ? kCG27GitHub : kCG27Channel];
    }];
    [alert addAction:open];
    alert.preferredAction = open;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CG27L(@"Reset settings?")
        message:CG27L(@"All settings return to defaults.") preferredStyle:UIAlertControllerStyleAlert];
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
                                         CFSTR("com.bazik1337.ios2627anims/changed"), NULL, NULL, YES);
    [self reloadSpecifiers];
}

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
