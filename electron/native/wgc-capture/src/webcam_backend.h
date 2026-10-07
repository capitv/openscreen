#pragma once

enum class WebcamBackend { None, MediaFoundation, DirectShow };

// A failed MF reader can still own the device. Release it before opening the
// same selected camera in DirectShow, and release a failed DirectShow graph too.
template <typename TryMediaFoundation, typename Release, typename TryDirectShow>
WebcamBackend initializeWebcamBackend(
    TryMediaFoundation tryMediaFoundation,
    Release release,
    TryDirectShow tryDirectShow) {
    if (tryMediaFoundation()) {
        return WebcamBackend::MediaFoundation;
    }
    release();
    if (tryDirectShow()) {
        return WebcamBackend::DirectShow;
    }
    release();
    return WebcamBackend::None;
}
