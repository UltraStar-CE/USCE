// SPDX-License-Identifier: GPL-2.0-or-later
// The C boundary keeps RmlUi's C++ objects out of the Pascal game.
#include <RmlUi/Core.h>
#include "RmlUi_Renderer_GL3.h"
#include <SDL.h>
#include <SDL_image.h>
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#ifdef _WIN32
#define UI_EXPORT extern "C" __declspec(dllexport)
#else
#define UI_EXPORT extern "C" __attribute__((visibility("default")))
#endif

using Translate = const char* (*)(const char*);
using Log = void (*)(int, const char*);
static Translate translate;
static Log log_message;
static std::string last_error;
class System final : public Rml::SystemInterface {
    const std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
public:
    double GetElapsedTime() override {
        return std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    }
    bool LogMessage(Rml::Log::Type type, const Rml::String& message) override {
        if (log_message) log_message(int(type), message.c_str());
        return true;
    }
};
class Renderer final : public RenderInterface_GL3 {
    Rml::TextureHandle LoadTexture(Rml::Vector2i& dimensions, const Rml::String& source) override {
        SDL_Surface* loaded = IMG_Load(source.c_str());
        if (!loaded) return 0;
        SDL_Surface* rgba = SDL_ConvertSurfaceFormat(loaded, SDL_PIXELFORMAT_RGBA32, 0);
        SDL_FreeSurface(loaded);
        if (!rgba) return 0;
        dimensions = {rgba->w, rgba->h};
        // RmlUi uses premultiplied alpha. Copy rows because SDL pitch may include padding.
        std::vector<Rml::byte> pixels(size_t(rgba->w) * rgba->h * 4);
        for (int y = 0; y < rgba->h; ++y) {
            const auto* row = static_cast<unsigned char*>(rgba->pixels) + y * rgba->pitch;
            for (int x = 0; x < rgba->w; ++x) {
                auto* p = pixels.data() + (size_t(y) * rgba->w + x) * 4;
                for (int c = 0; c < 3; ++c) p[c] = (unsigned(row[x*4+c]) * row[x*4+3] + 127) / 255;
                p[3] = row[x*4+3];
            }
        }
        SDL_FreeSurface(rgba);
        return GenerateTexture(pixels, dimensions);
    }
};
static System system_interface;
static std::unique_ptr<Renderer> renderer;
static Rml::Context* context;
static Rml::ElementDocument* document;
struct Binding { Rml::Element* element; std::string attribute; };
static std::unordered_map<std::string, std::vector<Binding>> bindings;
static std::vector<Rml::Element*> controls;
static std::string pending_action;
static bool initialized;
static std::vector<Rml::byte> font_data;
static std::vector<Rml::byte> bold_font_data;

class Actions final : public Rml::EventListener {
public:
    void ProcessEvent(Rml::Event& event) override {
        // Queue actions. Never destroy a document while RmlUi is dispatching an event.
        if (auto* element = event.GetCurrentElement()) {
            if (event.GetId() == Rml::EventId::Click)
                pending_action = element->GetAttribute<Rml::String>("action", "");
            else {
                const auto target = element->GetAttribute<Rml::String>("focus-text-target", "");
                const auto key = element->GetAttribute<Rml::String>("focus-text-lang", "");
                if (document && !target.empty()) {
                    if (auto* label = document->GetElementById(target))
                        label->SetInnerRML(Rml::StringUtilities::EncodeRml(translate ? translate(key.c_str()) : key));
                }
            }
        }
    }
};
static Actions actions;

static void bind_tree(Rml::Element* element) {
    const auto key = element->GetAttribute<Rml::String>("lang", "");
    if (!key.empty()) {
        // SetInnerRML parses markup: translations must be escaped as plain text.
        element->SetInnerRML(Rml::StringUtilities::EncodeRml(translate ? translate(key.c_str()) : key));
    }
    for (const char* attribute : {"bind-text", "bind-value"}) {
        const auto name = element->GetAttribute<Rml::String>(attribute, "");
        if (!name.empty()) bindings[name].push_back({element, attribute});
    }
    if (element->HasAttribute("action")) {
        element->AddEventListener(Rml::EventId::Click, &actions);
        element->AddEventListener(Rml::EventId::Focus, &actions);
        element->AddEventListener(Rml::EventId::Mouseover, &actions);
        controls.push_back(element);
    }
    for (int i = 0; i < element->GetNumChildren(); ++i) bind_tree(element->GetChild(i));
}

UI_EXPORT const char* ui_error() { return last_error.c_str(); }
UI_EXPORT void ui_close_document() {
    bindings.clear(); controls.clear(); pending_action.clear();
    if (document) { document->Close(); document = nullptr; context->Update(); }
}
UI_EXPORT void ui_shutdown() {
    if (!initialized) return;
    ui_close_document();
    Rml::Shutdown();
    context = nullptr; renderer.reset(); font_data.clear(); bold_font_data.clear(); RmlGL3::Shutdown(); initialized = false;
}
UI_EXPORT int ui_initialize(Translate translator, Log logger, const char* font, const char* bold_font) {
    if (initialized) return 1;
    translate = translator; log_message = logger;
    if (!RmlGL3::Initialize(&last_error)) return 0;
    renderer = std::make_unique<Renderer>();
    if (!*renderer) { last_error = "OpenGL 3 frontend initialization failed"; renderer.reset(); return 0; }
    Rml::SetSystemInterface(&system_interface);
    Rml::SetRenderInterface(renderer.get());
    if (!Rml::Initialise()) { last_error = "RmlUi initialization failed"; renderer.reset(); return 0; }
    initialized = true;
    context = Rml::CreateContext("usce", {800, 600});
    std::ifstream file(std::filesystem::u8path(font), std::ios::binary);
    font_data.assign(std::istreambuf_iterator<char>(file), {});
    if (!context || font_data.empty() || !Rml::LoadFontFace(font_data, "ui", Rml::Style::FontStyle::Normal)) {
        last_error = "Frontend context/font unavailable"; ui_shutdown(); return 0;
    }
    if (bold_font && *bold_font) {
        std::ifstream bold_file(std::filesystem::u8path(bold_font), std::ios::binary);
        bold_font_data.assign(std::istreambuf_iterator<char>(bold_file), {});
        if (!bold_font_data.empty()) Rml::LoadFontFace(bold_font_data, "ui", Rml::Style::FontStyle::Normal, Rml::Style::FontWeight::Bold);
    }
    return 1;
}
UI_EXPORT int ui_open(const char* filename) {
    if (!initialized) return 0;
    ui_close_document();
    document = context->LoadDocument(filename);
    if (!document) { last_error = std::string("Cannot load frontend document: ") + filename; return 0; }
    bind_tree(document);
    document->Show(); context->Update();
    if (!controls.empty()) controls.front()->Focus();
    return 1;
}
UI_EXPORT void ui_set(const char* name, const char* value) {
    const auto found = bindings.find(name);
    if (found == bindings.end()) return; // Optional elements need no game-side defaults.
    for (const auto& binding : found->second) {
        if (binding.attribute == "bind-text") binding.element->SetInnerRML(Rml::StringUtilities::EncodeRml(value));
        else binding.element->SetAttribute("value", value);
    }
}
UI_EXPORT void ui_render(int width, int height, int foreground_only) {
    if (!document || width <= 0 || height <= 0) return;
    document->SetClass("foreground-only", foreground_only == 1);
    document->SetClass("background-only", foreground_only == 2);
    context->SetDimensions({width, height}); context->Update();
    renderer->SetViewport(width, height);
    renderer->BeginFrame(); context->Render(); renderer->EndFrame();
}
UI_EXPORT const char* ui_action() { return pending_action.c_str(); }
UI_EXPORT void ui_clear_action() { pending_action.clear(); }
UI_EXPORT void ui_mouse(int x, int y, int button, int down) {
    if (!document) return;
    context->ProcessMouseMove(x, y, 0);
    if (button >= 0) {
        if (down) context->ProcessMouseButtonDown(button, 0);
        else context->ProcessMouseButtonUp(button, 0);
    }
}
UI_EXPORT void ui_key(int key) {
    if (!document || controls.empty()) return;
    // Generic document-order navigation; no assumption about a screen's button count.
    auto it = std::find(controls.begin(), controls.end(), context->GetFocusElement());
    int index = it == controls.end() ? 0 : int(it - controls.begin());
    if (key == 1 || key == -1) {
        index = (index + int(controls.size()) + key) % int(controls.size());
        controls[index]->Focus();
    } else if (key == 0) pending_action = controls[index]->GetAttribute<Rml::String>("action", "");
}
