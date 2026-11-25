#include "DYDanmakuCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <new>

struct DYDanmakuCore {
    struct Particle {
        double born;
        double width;
        double speed;
        double screen;
        int32_t lane;
        double tail(double time) const { return screen + width - (time - born) * speed; }
    };
    std::array<Particle, 256> active{};
    int count = 0;
    int32_t lanes = 0;
    double screen = 0;
    double gap = 24;
};

DYDanmakuCore *DYDMCreate(void) { return new (std::nothrow) DYDanmakuCore; }
void DYDMDestroy(DYDanmakuCore *core) { delete core; }
void DYDMReset(DYDanmakuCore *core) { if (core) core->count = 0; }

void DYDMConfigure(DYDanmakuCore *core, double screen, int32_t lanes, double gap) {
    if (!core) return;
    core->screen = std::max(0.0, screen);
    core->lanes = std::max<int32_t>(0, std::min<int32_t>(64, lanes));
    core->gap = std::max(0.0, gap);
}

double DYDMTravelSeconds(double width, double screen) {
    const double ratio = std::max(0.0, std::min(1.0, width / std::max(screen * 0.6, 1.0)));
    return 8.5 - 2.5 * ratio;
}

void DYDMAdvance(DYDanmakuCore *core, double time) {
    if (!core) return;
    int remaining = 0;
    for (int i = 0; i < core->count; ++i) {
        const auto &particle = core->active[i];
        if (particle.tail(time) >= 0) {
            core->active[remaining++] = particle;
        }
    }
    core->count = remaining;
}

int32_t DYDMTrySpawn(DYDanmakuCore *core, double time, double width) {
    if (!core || !std::isfinite(time) || !std::isfinite(width) || width <= 0 ||
        core->screen <= 0 || core->count == static_cast<int>(core->active.size())) return -1;
    const double speed = (core->screen + width) / DYDMTravelSeconds(width, core->screen);
    std::array<const DYDanmakuCore::Particle *, 64> tails{};
    for (int i = 0; i < core->count; ++i) {
        const auto &particle = core->active[i];
        const auto *previous = tails[particle.lane];
        if (!previous || particle.born >= previous->born) tails[particle.lane] = &particle;
    }
    for (int32_t lane = 0; lane < core->lanes; ++lane) {
        const auto *previous = tails[lane];
        if (previous) {
            const double tail = previous->tail(time);
            const double distance = core->screen - tail - core->gap;
            if (distance < 0) continue;
            if (speed > previous->speed && distance / (speed - previous->speed) < tail / previous->speed) continue;
        }
        core->active[core->count++] = {time, width, speed, core->screen, lane};
        return lane;
    }
    return -1;
}
