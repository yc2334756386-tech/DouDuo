#import "DGCommon.h"
#import "DGMusicIndex.h"
#include "MediaSources.hpp"

namespace {
std::vector<std::string> SourceURLs(id value) {
    std::vector<std::string> urls;
    for (id item in Array(value)) {
        if (![item isKindOfClass:NSString.class]) continue;
        std::string url=String(item);
        if (url.starts_with("//")) url="https:"+url;
        if (url.starts_with("https://")||url.starts_with("http://")) urls.push_back(std::move(url));
    }
    return urls;
}
double FiniteNumber(id value) {
    if(![value respondsToSelector:@selector(doubleValue)])return 0;
    double number=[value doubleValue];return std::isfinite(number)?std::max(0.,number):0;
}
void AddVariant(NSMutableDictionary *variants,NSString *key,const douglass::PlaybackSource &source) {
    if(!source.primary.empty())variants[key]=@{@"play":Text(source.primary),@"alternate":Text(source.alternate),@"fps":@(source.fps),@"shortSide":@(source.shortSide)};
}
}
NSArray *DGNormalizeWebItems(id items) {
    NSArray *rows=Array(items);
    NSMutableArray *results=[NSMutableArray arrayWithCapacity:rows.count];
    for(id raw in rows){
        if(![raw isKindOfClass:NSDictionary.class])continue;
        NSDictionary *row=raw;
        id manifest=row[@"mediaSources"];
        if(![manifest isKindOfClass:NSDictionary.class]){[results addObject:row];continue;}
        NSDictionary *media=manifest;
        std::vector<douglass::MediaSource> variants;
        for(id value in Array(media[@"candidates"])){
            if(![value isKindOfClass:NSDictionary.class])continue;
            NSDictionary *candidate=value;
            variants.push_back({SourceURLs(candidate[@"urls"]),FiniteNumber(candidate[@"shortSide"]),FiniteNumber(candidate[@"bitrate"]),FiniteNumber(candidate[@"fps"]),[candidate[@"avc"]boolValue]});
        }
        const auto selected=douglass::selectPlaybackSources(SourceURLs(media[@"urls"]),variants);
        if(selected.standard.primary.empty()&&!Array(row[@"images"]).count)continue;
        NSMutableDictionary *result=[row mutableCopy];
        [result removeObjectForKey:@"mediaSources"];
        result[@"play"]=Text(selected.standard.primary);result[@"alternate"]=Text(selected.standard.alternate);
        NSMutableDictionary *options=[NSMutableDictionary dictionary];
        AddVariant(options,@"quality",selected.quality);AddVariant(options,@"smooth",selected.smooth);AddVariant(options,@"qualityFPS",selected.qualityFPS);
        result[@"variants"]=options;
        [results addObject:result];
    }
    DGIndexMusicWorks(results);return results;
}
