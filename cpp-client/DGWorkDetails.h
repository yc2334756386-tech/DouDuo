#pragma once
#import "DGCommon.h"
BOOL DGWorkNeedsDetails(NSDictionary *record);
void DGResolveWorkDetails(DGBridge *bridge,NSDictionary *record,BOOL priority,DGResult completion);
