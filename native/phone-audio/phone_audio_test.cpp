#include "pcm_queue.h"
#include <cassert>
#include <iostream>
static std::vector<uint8_t> packet(uint32_t sequence) {
  std::vector<uint8_t> p(980);
  p[0] = 'U'; p[1] = 'A'; p[2] = 'P'; p[3] = '1';
  auto put = [&](int offset, uint32_t v) { for (int i = 0; i < 4; ++i) p[offset+i] = uint8_t(v >> (8*i)); };
  put(4, sequence); put(8, 48000); put(12, 480);
  for (int i = 0; i < 480; ++i) { p[20+i*2] = 0; p[21+i*2] = 64; }
  return p;
}
int main() {
  PcmQueue q;
  auto now = PcmQueue::Clock::now();
  auto p = packet(1);
  assert(q.push(p.data(), p.size(), now));
  assert(q.peak == 0.5f);
  assert(!q.push(p.data(), p.size(), now));
  p = packet(3); assert(q.push(p.data(), p.size(), now));
  assert(q.gaps == 1 && q.samples.size() == 1440);
  int16_t out[9600];
  assert(q.read(out, 9600, now) == 1440);
  assert(out[0] == 16384 && out[480] == 0 && out[960] == 16384);
  p[8] = 0; assert(!q.push(p.data(), p.size(), now));
  for (int i = 4; i < 40; ++i) { p = packet(i); assert(q.push(p.data(), p.size(), now)); }
  assert(q.samples.size() == PcmQueue::limit && q.dropped > 0);
  assert(q.read(out, 9600, now + std::chrono::milliseconds(251)) == 0);
  p = packet(0xffffffff); assert(q.push(p.data(), p.size(), now));
  p = packet(0); assert(q.push(p.data(), p.size(), now));
  p = packet(1); p.resize(24); assert(!q.push(p.data(), p.size(), now));
  std::cout << "PCM validation, gaps, stale frames, bounds and sequence wrap passed\n";
}
