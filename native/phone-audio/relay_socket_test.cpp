#include "phone_audio.h"
#include <rtc/rtc.hpp>
#include <nlohmann/json.hpp>
#include <cassert>
#include <atomic>
#include <chrono>
#include <iostream>
#include <mutex>
#include <thread>

template <typename Check> static void waitFor(Check check) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (!check()) {
    assert(std::chrono::steady_clock::now() < deadline);
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
}
int main(int argc, char **argv) {
  assert(!usce_relay_create(nullptr));
  assert(!usce_relay_create("https://example.invalid/"));
  assert(usce_relay_state(nullptr) == 3);
  assert(usce_relay_send(nullptr, "{}") == -1);
  assert(usce_relay_receive(nullptr, nullptr, 0) == -1);
  rtc::WebSocketServer::Configuration config;
  config.port = 0;
  config.bindAddress = "127.0.0.1";
  config.maxMessageSize = 1024 * 1024;
  auto server = std::make_unique<rtc::WebSocketServer>(config);
  std::mutex mutex;
  std::shared_ptr<rtc::WebSocket> peer;
  const bool sessionFixture = argc == 2 && std::string(argv[1]) == "--session-server";
  auto closed = std::make_shared<std::atomic<int>>(0);
  server->onClient([&](std::shared_ptr<rtc::WebSocket> client) {
    std::weak_ptr<rtc::WebSocket> weak = client;
    client->onClosed([closed] { ++*closed; });
    client->onMessage([weak, sessionFixture](rtc::message_variant message) {
      auto socket = weak.lock();
      if (!socket) return;
      if (!sessionFixture) { socket->send(std::move(message)); return; }
      try {
        auto text = std::get_if<std::string>(&message);
        if (!text) return;
        auto request = nlohmann::json::parse(*text);
        const auto type = request.value("type", "");
        if (type == "host.hello") {
          const bool resumed = request.value("roomId", "") == "fixture-room" &&
            request.value("hostToken", "") == "fixture-token";
          socket->send(nlohmann::json({{"type", resumed ? "room.resumed" : "room.created"},
            {"protocol", 1}, {"roomId", "fixture-room"}, {"hostToken", "fixture-token"},
            {"displayCode", "TEST"}}).dump());
        } else if (type == "host.heartbeat") {
          socket->send(std::string("{\"type\":\"ack\",\"protocol\":1,\"accepted\":true}"));
        } else if (type == "host.shutdown") socket->close();
      } catch (...) { socket->close(); }
    });
    std::lock_guard<std::mutex> lock(mutex);
    peer = std::move(client);
  });
  const auto address = "ws://127.0.0.1:" + std::to_string(server->port()) + "/ws/host";
  if (argc == 2 && (std::string(argv[1]) == "--echo-server" || sessionFixture)) {
    // A bounded fixture for exercising the actual Pascal DLL binding.
    std::cout << address << std::endl;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(20);
    while (*closed < 2 && std::chrono::steady_clock::now() < deadline)
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (peer) { peer->resetCallbacks(); peer->close(); peer.reset(); }
    }
    server->stop(); server.reset();
    return 0;
  }
  auto relay = usce_relay_create(address.c_str());
  assert(relay);
  waitFor([&] { return usce_relay_state(relay) == 1; });
  auto audio = usce_pa_create("ipc://", "");
  assert(audio);
  assert(usce_relay_send(relay, "") == -1);
  const std::string text = "{\"type\":\"control.command\",\"text\":\"Grüße 🎤\"}";
  assert(usce_relay_send(relay, text.c_str()) == 1);
  char small[2], buffer[4096];
  waitFor([&] { return usce_relay_receive(relay, small, sizeof(small)) == -2; });
  assert(usce_relay_receive(relay, buffer, sizeof(buffer)) == int32_t(text.size()));
  assert(std::string(buffer) == text);
  assert(usce_relay_receive(relay, buffer, sizeof(buffer)) == 0);
  assert(usce_relay_send(relay, std::string(1024 * 1024 + 1, 'x').c_str()) == -1);
  std::shared_ptr<rtc::WebSocket> sender;
  waitFor([&] {
    std::lock_guard<std::mutex> lock(mutex);
    sender = peer;
    return sender && sender->isOpen();
  });
  // No silent loss when a stopped Pascal consumer fills its receive queue.
  for (int i = 0; i < 129; ++i) sender->send(std::string("{}"));
  waitFor([&] { return usce_relay_state(relay) == 3; });
  usce_relay_destroy(relay);
  // Destroying the relay must not tear down the active microphone library.
  assert(usce_pa_status(audio, buffer, sizeof(buffer)) > 0);
  sender->resetCallbacks(); sender->close(); sender.reset();
  {
    std::lock_guard<std::mutex> lock(mutex);
    peer.reset();
  }
  // Unix symbol interposition can make the executable and DLL share RTC's
  // global lifetime. Release the fixture before the final native Cleanup wait.
  server->stop(); server.reset();
  usce_pa_destroy(audio);
  std::cout << "Relay loopback, UTF-8, short buffers, bounds, overflow and shared audio lifetime passed\n";
}
