#pragma once
#import "DGCommon.h"
void DGIndexMusicWorks(NSArray<NSDictionary *> *records);
NSArray<NSDictionary *> *DGIndexedMusicWorks(NSString *musicID);
void DGRememberMusicArtwork(NSString *musicID,NSString *cover);
NSString *DGKnownMusicArtwork(NSString *musicID);
NSString *DGMusicArtworkForRecord(NSDictionary *work);
