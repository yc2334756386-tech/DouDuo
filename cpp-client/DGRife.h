#pragma once
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#include <array>
#include <atomic>

BOOL DGRifeAvailable(void);
BOOL DGRifeRequested(void);

class DGRife {
public:
    DGRife();
    ~DGRife();
    DGRife(const DGRife &)=delete;
    DGRife &operator=(const DGRife &)=delete;
    // The caller owns the returned buffers at phases 1/4, 1/2 and 3/4.
    std::array<CVPixelBufferRef,3> copyInterpolatedFrames(CVPixelBufferRef previous,CVPixelBufferRef current,
                                                          double midpointDeadline,double quarterDeadline,
                                                          const std::atomic_bool &cancelled);
    bool rejected() const;
private:
    struct State;
    State *state_;
};
