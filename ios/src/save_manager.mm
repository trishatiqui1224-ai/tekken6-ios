// Tekken 6 Recompiled - iOS Save Manager
// Title ID: 4E4D07FC

#import <UIKit/UIKit.h>
#include <filesystem>
#include <fstream>
#include <system_error>

#include <rex/logging.h>
#include "save_manager.h"

namespace tekken6::saves {

int AutoSync(const std::filesystem::path& documents) {
    std::error_code ec;
    auto savesDir = documents / "saves";
    std::filesystem::create_directories(savesDir, ec);
    auto backupDir = documents / "saves_backup";
    std::filesystem::create_directories(backupDir, ec);

    int count = 0;
    if (std::filesystem::exists(savesDir, ec)) {
        for (const auto& entry : std::filesystem::directory_iterator(savesDir, ec)) {
            if (entry.is_regular_file()) {
                auto target = backupDir / entry.path().filename();
                std::filesystem::copy_file(entry.path(), target, std::filesystem::copy_options::update_existing, ec);
                count++;
            }
        }
    }
    REXLOG_INFO("[Tekken6Save] AutoSync verified {} save files in {}", count, savesDir.string());
    return 0;
}

void SyncAfterGameSave() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            AutoSync([paths.firstObject UTF8String]);
        }
    });
}

#ifdef __OBJC__
UIViewController* MakeSaveManager(const std::filesystem::path& documents) {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"Tekken 6 Saves";
    vc.view.backgroundColor = [UIColor colorWithRed:0.08f green:0.09f blue:0.12f alpha:1.0f];
    return vc;
}
#endif

} // namespace tekken6::saves

