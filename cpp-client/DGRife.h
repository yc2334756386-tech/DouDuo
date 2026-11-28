#pragma once
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#include <atomic>

BOOL DGRifeAvailable(void);
BOOL DGRifeRequested(void);

class DGRife {
public:
    DGRife();
    ~DGRife();
    DGRife(const DGRife &)=delete;
    DGRife &operator=(const DGRife &)=delete;
    CVPixelBufferRef copyMidpoint(CVPixelBufferRef previous,CVPixelBufferRef current,double deadline,
                                 const std::atomic_bool &cancelled);
    bool rejected() const;
private:
    struct State;
    State *state_;
};
