#pragma once
#include "pcm_queue.h"
#include <array>

// Bounded retained PCM, indexed by captured time in the game clock domain.
// A missing packet remains a hole until that packet arrives. Reading a
// window has no effect on subsequent readers or on the legacy FIFO.
class CaptureHistory {
  static constexpr uint32_t samplesPerPacket = 480;
  static constexpr uint32_t packetCount = 128;
  struct Packet {
    int64_t endUs = 0;
    uint32_t sequence = 0, firstSample = 0, captureEpoch = 0;
    std::array<int16_t, samplesPerPacket> samples{};
  };
  std::array<Packet, packetCount> packets{};
  uint32_t newestSequence = 0;
  bool started = false;

public:
  void push(const uint8_t *data, size_t size, int64_t endUs, int64_t hostNowUs,
            uint32_t captureEpoch = 0) {
    if (size != 980 || PcmQueue::u32(data) != 0x31504155 ||
        PcmQueue::u32(data + 8) != 48000 || PcmQueue::u32(data + 12) != samplesPerPacket ||
        endUs <= 0 || hostNowUs <= 0 ||
        endUs < hostNowUs - 1500000 || endUs > hostNowUs + 50000) return;
    const auto sequence = PcmQueue::u32(data + 4);
    if (started) {
      const auto delta = static_cast<int32_t>(sequence - newestSequence);
      if (delta <= -static_cast<int32_t>(packetCount)) return;
      if (delta >= static_cast<int32_t>(packetCount)) packets = {};
      if (delta > 0) newestSequence = sequence;
    } else {
      started = true;
      newestSequence = sequence;
    }
    auto &packet = packets[sequence % packetCount];
    if (packet.endUs && packet.sequence == sequence) return;
    packet.endUs = endUs;
    packet.sequence = sequence;
    packet.firstSample = PcmQueue::u32(data + 16);
    packet.captureEpoch = captureEpoch;
    for (uint32_t i = 0; i < samplesPerPacket; ++i) {
      const auto sample = uint16_t(data[20 + 2*i]) | (uint16_t(data[21 + 2*i]) << 8);
      packet.samples[i] = static_cast<int16_t>(sample);
    }
  }

  bool read(int64_t targetEndUs, int16_t *out, uint32_t count) {
    if (!out || !count || count > 4096 || targetEndUs <= 0) return false;
    const Packet *end = nullptr;
    int64_t best = 7001;
    const Packet *bracketEnd = nullptr;
    uint32_t bracketSkip = 0;
    for (const auto &packet : packets) {
      if (!packet.endUs || newestSequence - packet.sequence >= packetCount) continue;
      // The caller bounds both clocks to the game session's monotonic range.
      const auto delta = packet.endUs - targetEndUs;
      const auto distance = delta < 0 ? -delta : delta;
      if (distance < best) { end = &packet; best = distance; }
      if (delta < 0 || delta >= 20000 || (bracketEnd && packet.endUs >= bracketEnd->endUs)) continue;
      const auto &previous = packets[(packet.sequence - 1) % packetCount];
      const auto step = packet.endUs - previous.endUs;
      if (!contiguous(previous, packet) || !validTimeStep(step) || delta >= step) continue;
      bracketEnd = &packet;
      bracketSkip = static_cast<uint32_t>((delta * samplesPerPacket + step / 2) / step);
    }
    uint32_t skip = 0;
    if (bracketEnd) {
      end = bracketEnd;
      skip = bracketSkip;
    }
    if (!end) return false;
    const auto chunks = (count + skip + samplesPerPacket - 1) / samplesPerPacket;
    for (uint32_t i = 1; i < chunks; ++i) {
      const auto &next = packets[(end->sequence - i + 1) % packetCount];
      const auto &prev = packets[(end->sequence - i) % packetCount];
      if (!contiguous(prev, next)) return false;
    }
    for (uint32_t remaining = count, i = 0; remaining != 0; ++i) {
      const auto &packet = packets[(end->sequence - i) % packetCount];
      const auto take = std::min(remaining, samplesPerPacket - skip);
      remaining -= take;
      const auto stop = packet.samples.end() - skip;
      std::copy(stop - take, stop, out + remaining);
      skip = 0;
    }
    return true;
  }
private:
  static bool contiguous(const Packet &a, const Packet &b) {
    // Source continuity is distinct from the quality of its wall-clock fit.
    // Keep the legacy timestamp check when the sender has no explicit epoch.
    return consecutiveSamples(a,b) && a.captureEpoch == b.captureEpoch &&
      (b.captureEpoch || validTimeStep(b.endUs - a.endUs));
  }
  static bool consecutiveSamples(const Packet &a, const Packet &b) {
    return a.endUs && b.endUs && b.sequence - a.sequence == 1 &&
      b.firstSample - a.firstSample == samplesPerPacket;
  }
  static bool validTimeStep(int64_t step) {
    return step >= 4000 && step <= 20000;
  }
};
