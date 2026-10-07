#include "webcam_backend.h"

#include <cstdio>
#include <string>
#include <vector>

int main() {
    int failures = 0;
    const auto expect = [&](bool condition, const char* label) {
        if (!condition) {
            std::printf("FAIL %s\n", label);
            ++failures;
        }
    };
    // Model each failure point in the actual MF attempt, including configuration
    // after activation. A backend may hold the device even when it returns false.
    for (const std::string failure : {"startup", "selection", "configuration", "none"}) {
        for (const bool directShowAvailable : {false, true}) {
            std::vector<std::string> calls;
            bool ownsDevice = false;
            const auto backend = initializeWebcamBackend(
                [&] {
                    calls.push_back("mf-startup");
                    if (failure == "startup") return false;
                    calls.push_back("mf-selection");
                    ownsDevice = true;
                    if (failure == "selection") return false;
                    calls.push_back("mf-configuration");
                    return failure != "configuration";
                },
                [&] { calls.push_back("release"); ownsDevice = false; },
                [&] {
                    expect(!ownsDevice, "MF releases the device before DirectShow opens it");
                    calls.push_back("directshow");
                    ownsDevice = true;
                    return directShowAvailable;
                });
            std::vector<std::string> expected{"mf-startup"};
            if (failure != "startup") expected.push_back("mf-selection");
            if (failure == "configuration" || failure == "none") expected.push_back("mf-configuration");
            if (failure != "none") {
                expected.push_back("release");
                expected.push_back("directshow");
                if (!directShowAvailable) expected.push_back("release");
            }
            expect(calls == expected, "backend attempts and cleanup run in the required order");
            const auto wanted = failure == "none" ? WebcamBackend::MediaFoundation
                                : directShowAvailable ? WebcamBackend::DirectShow : WebcamBackend::None;
            expect(backend == wanted, "backend is committed only after successful initialization");
            expect(ownsDevice == (wanted != WebcamBackend::None), "failed attempts retain no camera ownership");
        }
    }
    if (!failures) std::puts("PASS webcam_backend_test: 8 startup/selection/configuration/fallback scenarios");
    return failures ? 1 : 0;
}
