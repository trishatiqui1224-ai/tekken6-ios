// Tekken 6 Recompiled - Main (main.cpp)
// Title ID: 4E4D07FC

#include "tekken6_app.h"
#include <rex/ui/windowed_app.h>

#if !defined(REX_PLATFORM_IOS)
int main(int argc, char* argv[]) {
    return rex::ui::WindowedAppMain<Tekken6App>(argc, argv);
}
#endif

