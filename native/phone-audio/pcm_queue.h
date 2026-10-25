#pragma once
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <deque>
#include <mutex>
#include <vector>

// Pure packet/buffer logic; shared by the receiver and its regression tests.
class PcmQueue {
public:
  using Clock = std::chrono::steady_clock;
  static constexpr size_t limit = 9600; // 200 ms, drop oldest on overload.
  std::deque<int16_t> samples;
  uint64_t packets = 0, gaps = 0, rejected = 0, duplicates = 0, dropped = 0;
  bool haveSequence = false;
  uint32_t sequence = 0;
  Clock::time_point last{};
  float peak = 0;
  double maxPacketIntervalMs = 0, maxQueuedMs = 0;
  static uint32_t u32(const uint8_t *p) {
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
  }
  void reset() { samples.clear(); haveSequence = false; peak = 0; last = {}; }
  bool push(const uint8_t *data, size_t size, Clock::time_point now = Clock::now()) {
    if (size < 20 || data[0] != 'U' || data[1] != 'A' || data[2] != 'P' || data[3] != '1') { ++rejected; return false; }
    const auto seq = u32(data + 4), rate = u32(data + 8), count = u32(data + 12);
    if (rate != 48000 || count != 480 || size != 20 + count * 2) { ++rejected; return false; }
    // Forget the old timeline after a stall; never score old buffered sound.
    if (last != Clock::time_point{}) {
      maxPacketIntervalMs = std::max(maxPacketIntervalMs, std::chrono::duration<double, std::milli>(now - last).count());
      if (now - last > std::chrono::milliseconds(250)) reset();
    }
    if (haveSequence) {
      const int32_t delta = static_cast<int32_t>(seq - sequence);
      if (delta <= 0) { ++duplicates; return false; }
      if (delta > 1) {
        gaps += uint32_t(delta - 1);
        // Preserve short gaps as silence. Large gaps restart the live window.
        if (delta <= 11) samples.insert(samples.end(), size_t(delta - 1) * 480, 0);
        else samples.clear();
      }
    }
    peak = 0;
    for (uint32_t i = 0; i < count; ++i) {
      const uint16_t value = uint16_t(data[20 + i * 2]) | (uint16_t(data[21 + i * 2]) << 8);
      const auto sample = static_cast<int16_t>(value);
      samples.push_back(sample);
      peak = std::max(peak, std::abs(float(sample)) / 32768.f);
    }
    while (samples.size() > limit) { samples.pop_front(); ++dropped; }
    maxQueuedMs = std::max(maxQueuedMs, samples.size() / 48.0);
    last = now; sequence = seq; haveSequence = true; ++packets;
    return true;
  }
  int32_t read(int16_t *out, int32_t capacity, Clock::time_point now = Clock::now()) {
    if (last == Clock::time_point{} || now - last > std::chrono::milliseconds(250)) { reset(); return 0; }
    const auto count = std::min(samples.size(), size_t(capacity));
    for (size_t i = 0; i < count; ++i) { out[i] = samples.front(); samples.pop_front(); }
    return int32_t(count);
  }
};
