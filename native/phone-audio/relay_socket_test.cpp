#include "phone_audio.h"
#include <rtc/rtc.hpp>
#include <cassert>
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
  rtc::WebSocketServer server(config);
  std::mutex mutex;
  std::shared_ptr<rtc::WebSocket> peer;
  server.onClient([&](std::shared_ptr<rtc::WebSocket> client) {
    std::weak_ptr<rtc::WebSocket> weak = client;
    client->onMessage([weak](rtc::message_variant message) {
      if (auto socket = weak.lock()) socket->send(std::move(message));
    });
    std::lock_guard<std::mutex> lock(mutex);
    peer = std::move(client);
  });
  const auto address = "ws://127.0.0.1:" + std::to_string(server.port()) + "/ws/host";
  if (argc == 2 && std::string(argv[1]) == "--echo-server") {
    // A bounded fixture for exercising the actual Pascal DLL binding.
    std::cout << address << std::endl;
    std::this_thread::sleep_for(std::chrono::seconds(20));
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (peer) { peer->resetCallbacks(); peer->close(); peer.reset(); }
    }
    server.stop();
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
  usce_pa_destroy(audio);
  sender->resetCallbacks(); sender->close(); sender.reset();
  {
    std::lock_guard<std::mutex> lock(mutex);
    peer.reset();
  }
  server.stop();
  std::cout << "Relay loopback, UTF-8, short buffers, bounds, overflow and shared audio lifetime passed\n";
}
