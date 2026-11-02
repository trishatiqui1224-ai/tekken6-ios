// Tekken 6 Recompiled - iOS Save Manager
// Title ID: 4E4D07FC

#pragma once

#include <filesystem>

#ifdef __OBJC__
@class UIViewController;

namespace tekken6::saves {
UIViewController* MakeSaveManager(const std::filesystem::path& documents);
}
#endif

namespace tekken6::saves {
int AutoSync(const std::filesystem::path& documents);
void SyncAfterGameSave();
}

