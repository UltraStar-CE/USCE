#pragma once
#include <chrono>
#include <cstdint>
// Caller synchronizes access. The game supplies its monotonic clock; the
// receiver extrapolates between updates so game-frame stalls do not inflate RTT.
class GameClockAnchor {
public:
  using Clock = std::chrono::steady_clock;
  bool ready = false;
  int64_t hostUs = 0;
  Clock::time_point sampledAt{};
  void set(int64_t value, Clock::time_point now = Clock::now()) {
    hostUs = value; sampledAt = now; ready = value > 0;
  }
  int64_t nowUs(Clock::time_point now = Clock::now()) const {
    return hostUs + std::chrono::duration_cast<std::chrono::microseconds>(now - sampledAt).count();
  }
};
