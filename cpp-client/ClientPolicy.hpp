#pragma once
#include <cstdint>
#include <string_view>

namespace douglass {
struct CountValue { std::int64_t value=0; bool known=false; };
CountValue parseCount(std::string_view text,bool provided);
bool isFollowing(std::int64_t status) noexcept;
bool matchesAuthor(std::string_view sec,std::string_view uid,std::string_view targetSec,std::string_view targetUID) noexcept;
double holdRate(double upward,double maximum) noexcept;
bool fillsPortrait(bool enabled,bool compact,bool photo,double width,double height) noexcept;
enum class AccountState { authenticated,signedOut,expired,unconfirmed };
AccountState assessAccount(bool requestOK,bool reportedSignedIn,std::string_view uid,
                          bool expired,bool sessionHint,unsigned attempt) noexcept;
}
