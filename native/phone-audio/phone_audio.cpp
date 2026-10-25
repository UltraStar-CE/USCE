#include "phone_audio.h"
#include "pcm_queue.h"
#include <rtc/rtc.hpp>
#include <nlohmann/json.hpp>
#include <atomic>
#include <cstring>
#include <memory>
#include <string>

using Json = nlohmann::json;
using Clock = PcmQueue::Clock;
namespace {
std::vector<uint8_t> decodePcm(const std::string &text) {
  static const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  if (text.size() != 1308) return {};
  std::vector<uint8_t> result;
  uint32_t bits = 0; int available = 0;
  for (char c : text) {
    if (c == '=') break;
    const auto v = alphabet.find(c);
    if (v == std::string::npos) return {};
    bits = (bits << 6) | uint32_t(v); available += 6;
    if (available >= 8) { available -= 8; result.push_back(uint8_t(bits >> available)); }
  }
  return result.size() == 980 ? result : std::vector<uint8_t>{};
}
struct Receiver : std::enable_shared_from_this<Receiver> {
  std::mutex mutex;
  PcmQueue pcm;
  std::deque<Json> incoming, outgoing;
  std::shared_ptr<rtc::WebSocket> socket;
  std::shared_ptr<rtc::PeerConnection> peer;
  std::shared_ptr<rtc::DataChannel> channel;
  std::string ice, code, player, error, state = "connecting";
  int attempt = 0;
  Clock::time_point heartbeat{};
  Clock::time_point previousPoll{};
  double maxPollIntervalMs = 0;
  Clock::time_point lastDirectPacket{}, lastDirectAck{};
  uint32_t directSequence = 0;
  std::atomic<bool> stopped{false};
  std::atomic<uint64_t> generation{0};

  void fail(const std::string &message) { error = message.substr(0, 240); }
  void enqueue(Json message, bool send = false) {
    std::lock_guard<std::mutex> lock(mutex);
    auto &queue = send ? outgoing : incoming;
    if (queue.size() < 128) queue.push_back(std::move(message));
  }
  void send(Json message) {
    message["protocol"] = 1;
    if (socket && socket->isOpen()) socket->send(message.dump());
  }
  void closePeer() {
    // Main thread only. Never hold mutex while native callbacks are drained.
    ++generation;
    if (peer) { peer->resetCallbacks(); peer->close(); peer.reset(); }
    std::shared_ptr<rtc::DataChannel> old;
    {
      std::lock_guard<std::mutex> lock(mutex);
      old.swap(channel);
      outgoing.clear(); pcm.reset(); lastDirectPacket = {}; state = "waiting for phone";
    }
    if (old) { old->resetCallbacks(); old->close(); }
  }
  void start(const std::string &url) {
    auto weak = weak_from_this();
    rtc::WebSocket::Configuration cfg;
    cfg.maxMessageSize = 128 * 1024;
    socket = std::make_shared<rtc::WebSocket>(cfg);
    socket->onOpen([weak] { if (auto self = weak.lock()) self->enqueue({{"type", "native.open"}}); });
    socket->onClosed([weak] { if (auto self = weak.lock()) self->enqueue({{"type", "native.closed"}}); });
    socket->onError([weak](std::string e) { if (auto self = weak.lock()) self->enqueue({{"type", "native.error"}, {"reason", e}}); });
    socket->onMessage([weak](rtc::message_variant data) {
      try {
        if (auto text = std::get_if<std::string>(&data)) {
          if (text->size() > 128 * 1024) return;
          auto message = Json::parse(*text);
          if (message.is_object()) if (auto self = weak.lock()) self->enqueue(std::move(message));
        }
      } catch (...) { /* Malformed signaling must not escape a native callback. */ }
    });
    socket->open(url);
  }
  void offer(const Json &message) {
    // Slot and player identity come from the authenticated relay, not audio data.
    if (message.value("slot", 0) != 1) return;
    closePeer();
    player = message.at("playerId").get<std::string>();
    attempt = message.value("attempt", 0);
    rtc::Configuration cfg;
    if (!ice.empty()) cfg.iceServers.emplace_back(ice);
    cfg.maxMessageSize = 4096;
    peer = std::make_shared<rtc::PeerConnection>(cfg);
    const auto weak = weak_from_this();
    const auto who = player;
    const auto serial = attempt;
    const auto gen = generation.load();
    peer->onLocalDescription([weak, who, serial](rtc::Description description) {
      if (auto self = weak.lock()) self->enqueue({{"type", "p2p.answer"}, {"playerId", who}, {"attempt", serial},
        {"description", {{"type", description.typeString()}, {"sdp", std::string(description)}}}}, true);
    });
    peer->onLocalCandidate([weak, who, serial](rtc::Candidate candidate) {
      if (auto self = weak.lock()) self->enqueue({{"type", "p2p.ice"}, {"playerId", who}, {"attempt", serial},
        {"candidate", {{"candidate", std::string(candidate)}, {"sdpMid", candidate.mid()}}}}, true);
    });
    peer->onStateChange([weak, gen](rtc::PeerConnection::State s) {
      if (auto self = weak.lock()) {
        if (self->generation != gen) return;
        if (s == rtc::PeerConnection::State::Failed || s == rtc::PeerConnection::State::Closed || s == rtc::PeerConnection::State::Disconnected)
          self->enqueue({{"type", "native.peer_closed"}, {"generation", gen}});
      }
    });
    peer->onDataChannel([weak, gen](std::shared_ptr<rtc::DataChannel> dc) {
      if (dc->label() != "usce-pcm-v1") { dc->close(); return; }
      if (auto self = weak.lock()) {
        {
          std::lock_guard<std::mutex> lock(self->mutex);
          if (self->stopped || self->generation != gen || self->channel) { dc->close(); return; }
          self->channel = dc;
        }
        std::weak_ptr<rtc::DataChannel> weakChannel = dc;
        dc->onMessage([weak, weakChannel, gen](rtc::message_variant payload) {
          try {
            // Echo on the receiver thread: excludes game-frame polling from RTT.
            if (auto text = std::get_if<std::string>(&payload)) {
              if (text->size() <= 256) {
                const auto ping = Json::parse(*text);
                if (ping.is_object() && ping.value("type", "") == "latency.ping")
                  if (auto ch = weakChannel.lock()) ch->send(*text);
              }
              return;
            }
            if (auto data = std::get_if<rtc::binary>(&payload)) if (auto owner = weak.lock()) {
              std::lock_guard<std::mutex> guard(owner->mutex);
              if (!owner->stopped && owner->generation == gen && data->size() <= 4096) {
                const auto *bytes = reinterpret_cast<const uint8_t *>(data->data());
                // A duplicate may have reached the game through the relay first.
                if (data->size() == 980 && bytes[0] == 'U' && bytes[1] == 'A' && bytes[2] == 'P' && bytes[3] == '1' &&
                    PcmQueue::u32(bytes + 8) == 48000 && PcmQueue::u32(bytes + 12) == 480) {
                  owner->lastDirectPacket = Clock::now(); owner->directSequence = PcmQueue::u32(bytes + 4);
                }
                if (owner->pcm.push(bytes, data->size())) owner->state = "receiving PCM";
              }
            }
          } catch (...) {}
        });
      }
    });
    {
      std::lock_guard<std::mutex> lock(mutex);
      state = "negotiating";
    }
    peer->setRemoteDescription(rtc::Description(message.at("description").at("sdp").get<std::string>(), "offer"));
  }
  void process(const Json &m) {
    const auto type = m.value("type", "");
    if (type == "native.open") {
      send({{"type", "host.hello"}, {"maxPlayers", 1}, {"gameVersion", "usce-native-pcm-prototype"},
        {"capabilities", Json::array({"p2pDataChannel", "rawPcmV1"})}});
    } else if (type == "room.created") {
      code = m.at("displayCode").get<std::string>();
      std::lock_guard<std::mutex> lock(mutex); state = "waiting for phone";
    } else if (type == "audio.pcm" && m.value("slot", 0) == 1) {
      auto bytes = decodePcm(m.value("pcm", ""));
      if (!bytes.empty()) {
        std::lock_guard<std::mutex> lock(mutex);
        if (pcm.push(bytes.data(), bytes.size())) state = "receiving PCM";
      }
    } else if (type == "p2p.offer") {
      offer(m);
    } else if (type == "p2p.ice" && peer && m.value("playerId", "") == player && m.value("attempt", 0) == attempt) {
      const auto &c = m.at("candidate");
      peer->addRemoteCandidate(rtc::Candidate(c.at("candidate").get<std::string>(), c.value("sdpMid", "0")));
    } else if ((type == "p2p.close" || type == "player.left" || type == "player.disconnected") && m.value("playerId", "") == player) {
      closePeer(); player.clear();
    } else if (type == "native.peer_closed" && m.value("generation", uint64_t(0)) == generation) {
      closePeer();
    } else if (type == "native.closed" || type == "native.error") {
      closePeer();
      { std::lock_guard<std::mutex> lock(mutex); state = "relay disconnected"; }
      fail(m.value("reason", "Restart the prototype to reconnect"));
    } else if (type == "error") fail(m.value("code", "relay error"));
  }
  void tick() {
    const auto now = Clock::now();
    if (previousPoll != Clock::time_point{}) maxPollIntervalMs = std::max(maxPollIntervalMs,
      std::chrono::duration<double, std::milli>(now - previousPoll).count());
    previousPoll = now;
    std::deque<Json> events, signals;
    { std::lock_guard<std::mutex> lock(mutex); events.swap(incoming); signals.swap(outgoing); }
    for (const auto &m : events) {
      try { process(m); } catch (const std::exception &e) { fail(e.what()); }
    }
    for (auto &m : signals) {
      if (m.value("playerId", "") == player && m.value("attempt", 0) == attempt) send(std::move(m));
    }
    if (Clock::now() - heartbeat > std::chrono::seconds(2)) { send({{"type", "host.heartbeat"}}); heartbeat = Clock::now(); }
  }
  void stop() {
    stopped = true;
    if (socket) { socket->resetCallbacks(); socket->close(); socket.reset(); }
    closePeer();
  }
};
using Handle = std::shared_ptr<Receiver>;
std::mutex lifecycleMutex;
size_t contextCount = 0;
}
int32_t usce_pa_version() { return 1; }
void *usce_pa_create(const char *url, const char *ice) {
  std::lock_guard<std::mutex> lock(lifecycleMutex);
  try {
    if (!url) return nullptr;
    auto self = std::make_shared<Receiver>();
    self->ice = ice ? ice : "";
    self->start(url);
    auto handle = new Handle(std::move(self));
    ++contextCount;
    return handle;
  } catch (...) {
    if (contextCount == 0) try { rtc::Cleanup().wait(); } catch (...) {}
    return nullptr;
  }
}
void usce_pa_destroy(void *p) {
  if (!p) return;
  std::lock_guard<std::mutex> lock(lifecycleMutex);
  auto handle = static_cast<Handle *>(p);
  try { (*handle)->stop(); } catch (...) {}
  delete handle;
  // Wait for the statically linked WebRTC worker threads before unloading DLL.
  if (--contextCount == 0) try { rtc::Cleanup().wait(); } catch (...) {}
}
int32_t usce_pa_poll(void *p, int16_t *samples, int32_t capacity) {
  if (!p || !samples || capacity <= 0 || capacity > 9600) return -1;
  try {
    const auto &self = *static_cast<Handle *>(p);
    self->tick();
    std::shared_ptr<rtc::DataChannel> channel;
    uint32_t sequence = 0;
    int32_t count;
    {
      std::lock_guard<std::mutex> lock(self->mutex);
      count = self->pcm.read(samples, capacity);
      const auto now = Clock::now();
      if (count > 0 && self->lastDirectPacket != Clock::time_point{} && now - self->lastDirectPacket < std::chrono::milliseconds(250) &&
          now - self->lastDirectAck > std::chrono::milliseconds(100)) {
        channel = self->channel; sequence = self->directSequence; self->lastDirectAck = now;
      }
    }
    try {
      if (channel && channel->isOpen()) channel->send(Json({{"type", "audio.pcm.ack"}, {"sequence", sequence}}).dump());
    } catch (...) { /* A lost acknowledgment must not discard drained audio. */ }
    return count;
  } catch (...) { return -1; }
}
int32_t usce_pa_status(void *p, char *buffer, int32_t capacity) {
  if (!p || !buffer || capacity <= 0) return -1;
  try {
    const auto &self = *static_cast<Handle *>(p);
    std::lock_guard<std::mutex> lock(self->mutex);
    const auto &q = self->pcm;
    const auto age = q.last == Clock::time_point{} ? -1 : std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - q.last).count();
    const auto text = Json({{"code", self->code}, {"state", self->state}, {"error", self->error},
      {"packets", q.packets}, {"gaps", q.gaps}, {"rejected", q.rejected}, {"droppedSamples", q.dropped},
      {"duplicateOrLatePackets", q.duplicates},
      {"queueMs", q.samples.size() / 48.0}, {"packetAgeMs", age}, {"peak", q.peak},
      {"maxQueueMs", q.maxQueuedMs}, {"maxPacketIntervalMs", q.maxPacketIntervalMs},
      {"maxGamePollIntervalMs", self->maxPollIntervalMs}}).dump();
    if (text.size() + 1 > size_t(capacity)) return -1;
    std::memcpy(buffer, text.c_str(), text.size() + 1);
    return int32_t(text.size());
  } catch (...) { return -1; }
}
