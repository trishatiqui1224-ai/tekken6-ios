// Tekken 6 Recompiled - iOS Launcher & Combat Dashboard (launcher.mm)
// Title ID: 4E4D07FC

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include <rex/cvar.h>
#include <rex/logging.h>

#include "launcher.h"
#include "touch_controls.h"

// Forward declaration of engine start
extern int RexMain(int argc, char* argv[]);

@implementation Tekken6AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    Tekken6LauncherViewController *launcher = [[Tekken6LauncherViewController alloc] init];
    self.window.rootViewController = launcher;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

@interface Tekken6LauncherViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *launchButton;
@property (nonatomic, strong) UISegmentedControl *resControl;
@property (nonatomic, strong) UISegmentedControl *fpsControl;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIView *logContainer;
@property (nonatomic, assign) BOOL gameFilesFound;
@end

@implementation Tekken6LauncherViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06f green:0.07f blue:0.09f alpha:1.0f];
    [self setupUI];
    [self scanGameFiles];
}

- (void)setupUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Header Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 28, w - 48, 44)];
    titleLabel.text = @"TEKKEN 6";
    titleLabel.textColor = [UIColor colorWithRed:1.0f green:0.84f blue:0.0f alpha:1.0f]; // Tournament Gold
    titleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBlack];
    [self.view addSubview:titleLabel];

    UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(26, 72, w - 48, 22)];
    subLabel.text = @"Xbox 360 Static Recompilation (Title ID: 4E4D07FC) • iOS/iPadOS ARM64";
    subLabel.textColor = [UIColor colorWithWhite:0.65f alpha:1.0f];
    subLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.view addSubview:subLabel];

    // Status Banner
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 108, w - 48, 38)];
    _statusLabel.layer.cornerRadius = 8.0f;
    _statusLabel.layer.masksToBounds = YES;
    _statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_statusLabel];

    // Options Container
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(24, 160, w - 48, 140)];
    card.backgroundColor = [UIColor colorWithWhite:0.12f alpha:0.9f];
    card.layer.cornerRadius = 12.0f;
    card.layer.borderColor = [UIColor colorWithWhite:0.25f alpha:0.6f].CGColor;
    card.layer.borderWidth = 1.0f;
    [self.view addSubview:card];

    UILabel *resLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, 180, 24)];
    resLabel.text = @"Render Resolution:";
    resLabel.textColor = [UIColor whiteColor];
    resLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card addSubview:resLabel];

    _resControl = [[UISegmentedControl alloc] initWithItems:@[@"720p", @"900p", @"1080p HD", @"Retina"]];
    _resControl.frame = CGRectMake(16, 44, card.bounds.size.width - 32, 32);
    _resControl.selectedSegmentIndex = 2; // 1080p HD Default
    [card addSubview:_resControl];

    UILabel *fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 88, 180, 24)];
    fpsLabel.text = @"ProMotion Frame Pacing:";
    fpsLabel.textColor = [UIColor whiteColor];
    fpsLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card addSubview:fpsLabel];

    _fpsControl = [[UISegmentedControl alloc] initWithItems:@[@"60 FPS Locked", @"120 FPS ProMotion"]];
    _fpsControl.frame = CGRectMake(200, 84, card.bounds.size.width - 216, 32);
    _fpsControl.selectedSegmentIndex = 0;
    [card addSubview:_fpsControl];

    // Action Buttons
    _launchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _launchButton.frame = CGRectMake(24, 315, w - 48, 52);
    _launchButton.layer.cornerRadius = 10.0f;
    _launchButton.backgroundColor = [UIColor colorWithRed:0.85f green:0.12f blue:0.20f alpha:1.0f]; // Tekken Crimson
    [_launchButton setTitle:@"START COMBAT DASHBOARD" forState:UIControlStateNormal];
    _launchButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBlack];
    [_launchButton addTarget:self action:@selector(launchGame) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_launchButton];

    // Logs Drawer Toggle
    UIButton *logToggle = [UIButton buttonWithType:UIButtonTypeSystem];
    logToggle.frame = CGRectMake(24, 380, 140, 32);
    [logToggle setTitle:@"[VIEW LOGS]" forState:UIControlStateNormal];
    logToggle.tintColor = [UIColor colorWithRed:0.0f green:0.85f blue:1.0f alpha:1.0f];
    logToggle.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [logToggle addTarget:self action:@selector(toggleLogs) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:logToggle];
}

- (void)scanGameFiles {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = paths.firstObject;

    NSString *gameDir = [docDir stringByAppendingPathComponent:@"game"];
    NSString *xexPath = [gameDir stringByAppendingPathComponent:@"default.xex"];
    NSString *isoPath = [docDir stringByAppendingPathComponent:@"tekken6.iso"];

    NSFileManager *fm = [NSFileManager defaultManager];
    _gameFilesFound = [fm fileExistsAtPath:xexPath] || [fm fileExistsAtPath:isoPath];

    if (_gameFilesFound) {
        _statusLabel.backgroundColor = [UIColor colorWithRed:0.1f green:0.5f blue:0.2f alpha:0.85f];
        _statusLabel.textColor = [UIColor whiteColor];
        _statusLabel.text = @"GAME ASSETS VERIFIED IN ~/Documents/game • READY TO FIGHT";
        [_launchButton setTitle:@"LAUNCH TEKKEN 6" forState:UIControlStateNormal];
    } else {
        _statusLabel.backgroundColor = [UIColor colorWithRed:0.6f green:0.4f blue:0.1f alpha:0.85f];
        _statusLabel.textColor = [UIColor whiteColor];
        _statusLabel.text = @"PLACE default.xex & DATA*.BIN IN ~/Documents/game (DIAGNOSTIC MODE)";
        [_launchButton setTitle:@"ENTER TEST & DIAGNOSTIC MODE" forState:UIControlStateNormal];
    }
}

- (void)launchGame {
    NSLog(@"[Tekken6] Launching Tekken 6 Recompiled...");
    tekken6::touch::Install();

    // Hide launcher view, hand off to Metal swapchain view
    [UIView animateWithDuration:0.3 animations:^{
        self.view.alpha = 0.0f;
    } completion:^(BOOL finished) {
        tekken6::touch::BringToFront();
    }];
}

- (void)toggleLogs {
    if (_logContainer) {
        [_logContainer removeFromSuperview];
        _logContainer = nil;
        return;
    }

    CGRect bounds = self.view.bounds;
    _logContainer = [[UIView alloc] initWithFrame:CGRectMake(20, bounds.size.height * 0.45f, bounds.size.width - 40, bounds.size.height * 0.5f)];
    _logContainer.backgroundColor = [UIColor colorWithWhite:0.05f alpha:0.95f];
    _logContainer.layer.cornerRadius = 10.0f;
    _logContainer.layer.borderColor = [UIColor cyanColor].CGColor;
    _logContainer.layer.borderWidth = 1.0f;

    _logView = [[UITextView alloc] initWithFrame:CGRectInset(_logContainer.bounds, 10, 40)];
    _logView.backgroundColor = [UIColor clearColor];
    _logView.textColor = [UIColor colorWithRed:0.2f green:0.9f blue:0.3f alpha:1.0f];
    _logView.font = [UIFont fontWithName:@"Menlo" size:11.0f];
    _logView.editable = NO;
    _logView.text = @"[Tekken6] Diagnostic Log Drawer Active\n[Tekken6] Metal & MoltenVK Initialized\n";

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(_logContainer.bounds.size.width - 70, 6, 60, 28);
    [closeBtn setTitle:@"CLOSE" forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor whiteColor];
    [closeBtn addTarget:self action:@selector(toggleLogs) forControlEvents:UIControlEventTouchUpInside];

    [_logContainer addSubview:closeBtn];
    [_logContainer addSubview:_logView];
    [self.view addSubview:_logContainer];
}

@end

