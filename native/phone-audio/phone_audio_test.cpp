#include "pcm_queue.h"
#include "game_clock.h"
#include "phone_audio.h"
#include <cassert>
#include <iostream>
#include <string>
static std::string base64(const std::vector<uint8_t> &bytes) {
  const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string text;
  for (size_t i = 0; i < bytes.size(); i += 3) {
    const uint32_t value = (uint32_t(bytes[i]) << 16) |
      (i + 1 < bytes.size() ? uint32_t(bytes[i+1]) << 8 : 0) |
      (i + 2 < bytes.size() ? bytes[i+2] : 0);
    text += alphabet[(value >> 18) & 63]; text += alphabet[(value >> 12) & 63];
    text += i + 1 < bytes.size() ? alphabet[(value >> 6) & 63] : '=';
    text += i + 2 < bytes.size() ? alphabet[value & 63] : '=';
  }
  return text;
}
static std::vector<uint8_t> packet(uint32_t sequence) {
  std::vector<uint8_t> p(980);
  p[0] = 'U'; p[1] = 'A'; p[2] = 'P'; p[3] = '1';
  auto put = [&](int offset, uint32_t v) { for (int i = 0; i < 4; ++i) p[offset+i] = uint8_t(v >> (8*i)); };
  put(4, sequence); put(8, 48000); put(12, 480);
  put(16, sequence * 480);
  for (int i = 0; i < 480; ++i) { p[20+i*2] = 0; p[21+i*2] = 64; }
  return p;
}
int main() {
  GameClockAnchor anchor;
  const auto epoch = GameClockAnchor::Clock::time_point{};
  assert(!anchor.ready);
  anchor.set(123456000, epoch);
  assert(anchor.ready);
  assert(anchor.nowUs(epoch + std::chrono::microseconds(137)) == 123456137);
  assert(anchor.nowUs(epoch + std::chrono::seconds(3)) == 126456000);
  anchor.set(99000000, epoch + std::chrono::seconds(4));
  assert(anchor.nowUs(epoch + std::chrono::milliseconds(4001)) == 99001000);
  anchor.set(0, epoch);
  assert(!anchor.ready);

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
  assert(q.readEndSampleCounter == 4 * 480);
  assert(out[0] == 16384 && out[480] == 0 && out[960] == 16384);
  p[8] = 0; assert(!q.push(p.data(), p.size(), now));
  for (int i = 4; i < 40; ++i) { p = packet(i); assert(q.push(p.data(), p.size(), now)); }
  assert(q.samples.size() == PcmQueue::limit && q.dropped > 0);
  assert(q.read(out, 9600, now + std::chrono::milliseconds(251)) == 0);
  p = packet(0xffffffff); assert(q.push(p.data(), p.size(), now));
  p = packet(0); assert(q.push(p.data(), p.size(), now));
  p = packet(1); p.resize(24); assert(!q.push(p.data(), p.size(), now));
  auto receiver = usce_pa_create("ipc://", "");
  assert(receiver);
  assert(usce_pa_signal(receiver, "{\"type\":\"bridge.ready\",\"displayCode\":null}") == 0);
  assert(usce_pa_signal(receiver, "not json") == -1);
  assert(usce_pa_signal(receiver, "{\"type\":\"room.created\",\"displayCode\":\"TEST\"}") == 0);
  const auto pcm = std::string("{\"type\":\"audio.pcm\",\"slot\":1,\"pcm\":\"") + base64(packet(1)) + "\"}";
  assert(usce_pa_signal(receiver, pcm.c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  assert(out[0] == 16384);
  auto calibrationPacket = packet(2);
  calibrationPacket[2] = 'C';
  const auto calibrationMessage = std::string("{\"type\":\"audio.calibration.pcm\",\"slot\":1,\"pcm\":\"") + base64(calibrationPacket) + "\"}";
  const auto wronglyLabelled = std::string("{\"type\":\"audio.pcm\",\"slot\":1,\"pcm\":\"") + base64(calibrationPacket) + "\"}";
  assert(usce_pa_signal(receiver, calibrationMessage.c_str()) == 0);
  assert(usce_pa_signal(receiver, wronglyLabelled.c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 0); // Calibration cannot become a singing sample.
  assert(usce_pa_poll_calibration(receiver, out, 9600) == 480);
  assert(out[0] == 16384);
  const auto realMicrophone = std::string("{\"type\":\"audio.pcm\",\"slot\":1,\"pcm\":\"") + base64(packet(2)) + "\"}";
  assert(usce_pa_signal(receiver, realMicrophone.c_str()) == 0);
  assert(usce_pa_poll_calibration(receiver, out, 9600) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480); // Same sequence, independent queues.
  char status[4096];
  assert(usce_pa_status(receiver, status, sizeof(status)) > 0);
  assert(std::string(status).find("TEST") != std::string::npos);
  assert(usce_pa_event(receiver, status, sizeof(status)) == 0);
  auto second = usce_pa_create("ipc://", "");
  assert(second);
  assert(usce_pa_signal(receiver, "{\"type\":\"player.assigned\",\"playerId\":\"one\",\"slot\":1}") == 0);
  assert(usce_pa_signal(second, "{\"type\":\"player.assigned\",\"playerId\":\"two\",\"slot\":1}") == 0);
  const auto firstPcm = std::string("{\"type\":\"audio.pcm\",\"playerId\":\"one\",\"slot\":1,\"pcm\":\"") + base64(packet(1)) + "\"}";
  const auto secondPcm = std::string("{\"type\":\"audio.pcm\",\"playerId\":\"two\",\"slot\":1,\"pcm\":\"") + base64(packet(1)) + "\"}";
  assert(usce_pa_signal(receiver, firstPcm.c_str()) == 0);
  assert(usce_pa_signal(second, secondPcm.c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  assert(usce_pa_poll(second, out, 9600) == 480);
  const auto secondCalibration = std::string("{\"type\":\"audio.calibration.pcm\",\"playerId\":\"two\",\"slot\":1,\"pcm\":\"") + base64(calibrationPacket) + "\"}";
  assert(usce_pa_signal(second, secondCalibration.c_str()) == 0);
  assert(usce_pa_poll(second, out, 9600) == 0); // Leave calibration queued independently.
  // Moving a phone clears its old lane, including queued PCM and sequence state.
  assert(usce_pa_signal(second, "{\"type\":\"player.assigned\",\"playerId\":\"two\",\"slot\":0}") == 0);
  assert(usce_pa_signal(second, secondPcm.c_str()) == 0);
  assert(usce_pa_poll_calibration(second, out, 9600) == 0);
  assert(usce_pa_poll(second, out, 9600) == 0);
  assert(usce_pa_signal(second, "{\"type\":\"player.assigned\",\"playerId\":\"three\",\"slot\":1}") == 0);
  assert(usce_pa_signal(second, secondPcm.c_str()) == 0);
  assert(usce_pa_poll(second, out, 9600) == 0);
  usce_pa_destroy(second);
  usce_pa_destroy(receiver);
  std::cout << "PCM validation, gaps, stale frames, bounds and sequence wrap passed\n";
}
