#pragma once
#import <UIKit/UIKit.h>
void DGDiagnosticStart(void);
void DGDiagnosticEnable(BOOL enabled);
void DGDiagnostic(NSString *event,NSString *metrics);
void DGDiagnosticMemory(NSString *event);
void DGDiagnosticExport(UIViewController *host);
void DGDiagnosticClear(UIViewController *host);

BOOL DGDiagnosticEnabled(void);
void DGDiagnosticShow(UIViewController *host);
