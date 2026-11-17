#include "pcm_queue.h"
#include "capture_history.h"
#include "game_clock.h"
#include "phone_audio.h"
#include <cassert>
#include <iostream>
#include <string>
#include <thread>
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
  const auto continuousCapture = q.captureGeneration;
  p = packet(20);
  assert(q.push(p.data(), p.size(), now));
  assert(q.captureGeneration != continuousCapture);
  assert(q.read(out, 240, now) == 240);
  assert(q.readEndSampleCounter == 20 * 480 + 240);
  assert(q.read(out, 240, now) == 240);
  assert(q.readEndSampleCounter == 21 * 480);
  p[8] = 0; assert(!q.push(p.data(), p.size(), now));
  const auto beforeOverflow = q.captureGeneration;
  for (int i = 21; i < 49; ++i) { p = packet(i); assert(q.push(p.data(), p.size(), now)); }
  assert(q.samples.size() == PcmQueue::limit && q.dropped > 0);
  assert(q.captureGeneration != beforeOverflow);
  const auto beforeStall = q.captureGeneration;
  assert(q.read(out, 9600, now + std::chrono::milliseconds(251)) == 0);
  assert(q.captureGeneration != beforeStall);
  p = packet(0xffffffff); assert(q.push(p.data(), p.size(), now));
  p = packet(0); assert(q.push(p.data(), p.size(), now));
  p = packet(1); p.resize(24); assert(!q.push(p.data(), p.size(), now));
  CaptureHistory history;
  p = packet(1); history.push(p.data(), p.size(), 1010000, 1040000);
  p = packet(3);
  for (int i = 0; i < 480; ++i) p[21 + i*2] = 32;
  history.push(p.data(), p.size(), 1030000, 1040000);
  assert(history.read(1030000, out, 480));
  assert(!history.read(1030000, out, 1000));
  p = packet(2); history.push(p.data(), p.size(), 1020000, 1045000);
  assert(history.read(1030000, out, 1000));
  assert(out[0] == 16384 && out[999] == 8192);
  assert(history.read(1025000, out, 480));
  assert(out[239] == 16384 && out[240] == 8192);
  assert(history.read(1020000, out, 600)); // Historical selection is independent of newest packet.
  p = packet(4); history.push(p.data(), p.size(), 1060000, 1070000);
  assert(!history.read(1060000, out, 600)); // Timeline break even with consecutive sequence numbers.
  assert(!history.read(1075000, out, 480));
  CaptureHistory sourceClock;
  p = packet(1); sourceClock.push(p.data(), p.size(), 1010000, 1040000, 1);
  p = packet(2); sourceClock.push(p.data(), p.size(), 1040000, 1050000, 1);
  // Consecutive source PCM can cross a noisy timestamp correction.
  assert(sourceClock.read(1040000, out, 960));
  p = packet(3); sourceClock.push(p.data(), p.size(), 1050000, 1060000, 2);
  // A real capture interruption still rejects a window that spans it, even
  // when the timestamps look continuous.
  assert(!sourceClock.read(1050000, out, 960));
  CaptureHistory restarted;
  p = packet(5000);
  assert(restarted.push(p.data(), p.size(), 1000000, 1000000, 1));
  p = packet(0);
  assert(!restarted.push(p.data(), p.size(), 990000, 1400000, 1));
  assert(!restarted.push(p.data(), p.size(), 1010000, 1010000, 1));
  assert(restarted.push(p.data(), p.size(), 1300000, 1300000, 1));
  assert(restarted.read(1300000, out, 480));
  assert(!restarted.read(1000000, out, 480));
  CaptureHistory directCapture;
  p = packet(1);
  p.resize(CaptureHistory::stampedPcmBytes);
  const auto directStamp = uint64_t{1} << 33;
  for (size_t i = 0; i < 8; ++i)
    p[CaptureHistory::pcmBytes + i] = static_cast<uint8_t>(directStamp >> (8 * i));
  p[CaptureHistory::pcmBytes + 8] = 1;
  directCapture.pushStamped(p.data(), p.size() - 1, directStamp + 10000);
  assert(!directCapture.read(directStamp, out, 480));
  directCapture.pushStamped(p.data(), p.size(), directStamp + 10000);
  assert(directCapture.read(directStamp, out, 480));
  assert(out[0] == 16384);
  // A sequence number alone cannot identify a duplicate on the relay path.
  p = packet(3);
  assert(history.push(p.data(), p.size(), 1030000, 1070000));
  assert(!history.push(p.data(), p.size(), 1030001, 1070000));
  assert(!history.push(p.data(), p.size(), 1030000, 1070000, 2));
  assert(history.read(1030000, out, 480) && out[0] == 8192);

  auto receiver = usce_pa_create("ipc://", "");
  assert(receiver);
  assert(usce_pa_signal(receiver, "{\"type\":\"bridge.ready\",\"displayCode\":null}") == 0);
  assert(usce_pa_signal(receiver, "not json") == -1);
  assert(usce_pa_signal(receiver, "{\"type\":\"room.created\",\"displayCode\":\"TEST\"}") == 0);
  const auto timedPcm = [](int seq, int64_t stamp, const char *player = "", int epoch = 1) {
    return std::string("{\"type\":\"audio.pcm\",\"slot\":1,\"playerId\":\"") + player +
      "\",\"captureEpoch\":" + std::to_string(epoch) + ",\"captureEndHostUs\":" + std::to_string(stamp) +
      ",\"pcm\":\"" + base64(packet(seq)) + "\"}";
  };
  const auto unstamped = [](int seq) {
    return std::string("{\"type\":\"audio.pcm\",\"slot\":1,\"pcm\":\"") + base64(packet(seq)) + "\"}";
  };
  assert(usce_pa_signal(receiver, unstamped(0).c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  usce_pa_set_clock(receiver, 2000000);
  assert(usce_pa_signal(receiver, unstamped(1).c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  assert(usce_pa_signal(receiver, timedPcm(2, 100000).c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  assert(usce_pa_capture_window(receiver, 100000, out, 480) != 1);
  assert(usce_pa_signal(receiver, timedPcm(3, 1980000).c_str()) == 0);
  uint32_t generation = 0;
  assert(usce_pa_poll_generation(receiver, out, 200, &generation) == 200);
  assert(generation != 0);
  const auto firstGeneration = generation;
  assert(usce_pa_poll_generation(receiver, out, 9600, &generation) == 280);
  assert(generation == firstGeneration);
  assert(out[0] == 16384);
  auto calibrationPacket = packet(4);
  calibrationPacket[2] = 'C';
  const auto calibrationMessage = std::string("{\"type\":\"audio.calibration.pcm\",\"slot\":1,\"pcm\":\"") + base64(calibrationPacket) + "\"}";
  const auto wronglyLabelled = std::string("{\"type\":\"audio.pcm\",\"slot\":1,\"pcm\":\"") + base64(calibrationPacket) + "\"}";
  assert(usce_pa_signal(receiver, calibrationMessage.c_str()) == 0);
  assert(usce_pa_signal(receiver, wronglyLabelled.c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 0); // Calibration cannot become a singing sample.
  assert(usce_pa_poll_calibration(receiver, out, 9600) == 480);
  assert(out[0] == 16384);
  assert(usce_pa_signal(receiver, timedPcm(4, 1990000).c_str()) == 0);
  assert(usce_pa_poll_calibration(receiver, out, 9600) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480); // Same sequence, independent queues.
  assert(usce_pa_capture_window(receiver, 1990000, out, 480) == 1);
  char status[4096];
  assert(usce_pa_status(receiver, status, sizeof(status)) > 0);
  assert(std::string(status).find("TEST") != std::string::npos);
  assert(usce_pa_event(receiver, status, sizeof(status)) == 0);
  assert(usce_pa_signal(receiver, timedPcm(5000, 2000000).c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  usce_pa_set_clock(receiver, 2300000);
  assert(usce_pa_signal(receiver, timedPcm(0, 2300000).c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  assert(usce_pa_capture_window(receiver, 2300000, out, 480) == 1);
  assert(usce_pa_capture_window(receiver, 2000000, out, 480) != 1);
  assert(usce_pa_signal(receiver, timedPcm(5000, 2300000).c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  // A positively identified new source epoch recovers even before the stall timer.
  assert(usce_pa_signal(receiver, timedPcm(0, 2300001, "", 2).c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  const auto sendTimed = [&](void *audio, int sequence, int64_t stamp, int epoch = 1) {
    assert(usce_pa_signal(audio, timedPcm(sequence, stamp, "", epoch).c_str()) == 0);
    assert(usce_pa_poll(audio, out, 9600) >= 0);
  };
  const auto checkShortRestart = [&](int nextEpoch, int64_t restartPauseUs) {
    auto audio = usce_pa_create("ipc://", "");
    assert(audio);
    usce_pa_set_clock(audio, 3490000);
    for (int i = 0; i < 50; ++i)
      sendTimed(audio, i, 3000000 + i * 10000);
    assert(usce_pa_capture_window(audio, 3490000, out, 2048) == 1);

    const auto restartUs = 3490000 + restartPauseUs;
    usce_pa_set_clock(audio, restartUs);
    // The first packet would have been a sequence-only duplicate before the fix.
    sendTimed(audio, 0, restartUs, nextEpoch);
    assert(usce_pa_capture_window(audio, restartUs, out, 480) == 1);
    assert(usce_pa_capture_window(audio, 3490000, out, 480) != 1);
    for (int i = 1; i < 6; ++i)
      sendTimed(audio, i, restartUs + i * 10000, nextEpoch);
    assert(usce_pa_capture_window(audio, restartUs + 50000, out, 2048) == 1);
    usce_pa_destroy(audio);
  };
  checkShortRestart(2, 10000);  // New epoch even without a stall.
  checkShortRestart(1, 300000); // Same epoch after a stall.

  auto audio = usce_pa_create("ipc://", "");
  assert(audio);
  usce_pa_set_clock(audio, 4000000);
  sendTimed(audio, 5099, 4000000);
  usce_pa_set_clock(audio, 4340000);
  for (int i = 0; i < 5; ++i)
    sendTimed(audio, i, 4300000 + i * 10000, 2);
  assert(usce_pa_capture_window(audio, 4340000, out, 2048) == 1);
  // The delayed old epoch jumps forward in sequence, but not in capture time.
  sendTimed(audio, 5100, 4010000);
  // Neither can an old timestamp on a forward packet in the current epoch.
  sendTimed(audio, 5100, 4010000, 2);
  assert(usce_pa_capture_window(audio, 4340000, out, 2048) == 1);
  assert(usce_pa_capture_window(audio, 4010000, out, 480) != 1);
  usce_pa_destroy(audio);

  auto second = usce_pa_create("ipc://", "");
  assert(second);
  assert(usce_pa_signal(receiver, "{\"type\":\"player.assigned\",\"playerId\":\"one\",\"slot\":1}") == 0);
  assert(usce_pa_signal(second, "{\"type\":\"player.assigned\",\"playerId\":\"two\",\"slot\":1}") == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 0);
  assert(usce_pa_capture_window(receiver, 1990000, out, 480) != 1); // A new owner starts without timing history.
  usce_pa_set_clock(second, 2000000);
  const auto firstPcm = timedPcm(1, 1990000, "one");
  const auto secondPcm = timedPcm(1, 1990000, "two");
  assert(usce_pa_signal(receiver, firstPcm.c_str()) == 0);
  assert(usce_pa_signal(second, secondPcm.c_str()) == 0);
  assert(usce_pa_poll(receiver, out, 9600) == 480);
  assert(usce_pa_capture_window(receiver, 1990000, out, 480) == 1);
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
