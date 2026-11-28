#include "RenderBudget.hpp"
#include <algorithm>
#include <cmath>

namespace douglass {
std::uint64_t RenderBudget::begin(double now,double duration){
    if(!std::isfinite(now))return 0;
    active(now);
    duration=std::isfinite(duration)?std::clamp(duration,.05,30.):1.;
    const auto token=++next_;
    leases_.push_back({token,now+duration+.12});return token;
}
void RenderBudget::end(std::uint64_t token) noexcept{
    std::erase_if(leases_,[token](const Lease &lease){return lease.token==token;});
}
bool RenderBudget::active(double now) noexcept{
    if(!std::isfinite(now))return false;
    std::erase_if(leases_,[now](const Lease &lease){return now>=lease.until;});
    return !leases_.empty();
}
double RenderBudget::deadline(double now) noexcept{active(now);double result=0;for(const auto &lease:leases_)result=std::max(result,lease.until);return result;}
}
