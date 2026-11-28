#include "ExperimentalMedia.hpp"
#define NS_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#define MTLFX_PRIVATE_IMPLEMENTATION
#include "third-party/metal-cpp/MetalFX/MTLFXSpatialScaler.hpp"
namespace douglass {
bool experimentalMediaRequested(ExperimentalMediaFeature feature,bool stored) noexcept{return stored&&(feature==ExperimentalMediaFeature::spatialSampling||feature==ExperimentalMediaFeature::frameInterpolation);}
PicturePreset picturePreset(unsigned index) noexcept{switch(index){case 1:return {1.04,1.04,0};case 2:return {.88,.98,-.015};case 3:return {1.08,1.08,0};case 4:return {1,1,0,.14,.32};default:return {};}}
struct SpatialUpscaler::State{MTL::Device *device=nullptr;MTLFX::SpatialScaler *scaler=nullptr;unsigned iw=0,ih=0,ow=0,oh=0;~State(){if(scaler)scaler->release();if(device)device->release();}};
SpatialUpscaler::SpatialUpscaler(void *device):state_(std::make_unique<State>()){state_->device=reinterpret_cast<MTL::Device *>(device);if(state_->device)state_->device->retain();}
SpatialUpscaler::~SpatialUpscaler()=default;
bool SpatialUpscaler::encode(void *command,void *input,void *output){
 auto in=reinterpret_cast<MTL::Texture *>(input),out=reinterpret_cast<MTL::Texture *>(output);auto cmd=reinterpret_cast<MTL::CommandBuffer *>(command);auto &s=*state_;
 if(!s.device||!in||!out||!cmd||!MTLFX::SpatialScalerDescriptor::supportsDevice(s.device))return false;
 if(!s.scaler||s.iw!=in->width()||s.ih!=in->height()||s.ow!=out->width()||s.oh!=out->height()){
  if(s.scaler){s.scaler->release();s.scaler=nullptr;}auto descriptor=MTLFX::SpatialScalerDescriptor::alloc()->init();descriptor->setInputWidth(in->width());descriptor->setInputHeight(in->height());descriptor->setOutputWidth(out->width());descriptor->setOutputHeight(out->height());descriptor->setColorTextureFormat(in->pixelFormat());descriptor->setOutputTextureFormat(out->pixelFormat());descriptor->setColorProcessingMode(MTLFX::SpatialScalerColorProcessingModePerceptual);s.scaler=descriptor->newSpatialScaler(s.device);descriptor->release();s.iw=in->width();s.ih=in->height();s.ow=out->width();s.oh=out->height();
 }
 if(!s.scaler)return false;s.scaler->setColorTexture(in);s.scaler->setOutputTexture(out);s.scaler->setInputContentWidth(in->width());s.scaler->setInputContentHeight(in->height());s.scaler->encodeToCommandBuffer(cmd);return true;
}
}
