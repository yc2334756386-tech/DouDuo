#pragma once
#include <cstdint>
#include <vector>

namespace douglass {
// Owned by the UI thread. Expiring leases also cover cancelled UIKit animators.
class RenderBudget {
public:
    std::uint64_t begin(double now,double duration);
    void end(std::uint64_t token) noexcept;
    bool active(double now) noexcept;
private:
    struct Lease {std::uint64_t token;double until;};
    std::vector<Lease> leases_;
    std::uint64_t next_=0;
};
}
