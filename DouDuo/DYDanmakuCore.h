#ifndef DY_DANMAKU_CORE_H
#define DY_DANMAKU_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DYDanmakuCore DYDanmakuCore;
DYDanmakuCore *DYDMCreate(void);
void DYDMDestroy(DYDanmakuCore *core);
void DYDMReset(DYDanmakuCore *core);
void DYDMConfigure(DYDanmakuCore *core, double screen, int32_t lanes, double gap);
void DYDMAdvance(DYDanmakuCore *core, double time);
int32_t DYDMTrySpawn(DYDanmakuCore *core, double time, double width);
double DYDMTravelSeconds(double width, double screen);

#ifdef __cplusplus
}
#endif
#endif
