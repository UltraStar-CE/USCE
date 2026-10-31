// SPDX-License-Identifier: GPL-2.0-or-later
// The C boundary keeps RmlUi's C++ objects out of the Pascal game.
#include <RmlUi/Core.h>
#include <RmlUi/Core/Factory.h>
#include <RmlUi/Core/StyleSheetContainer.h>
#include "RmlUi_Renderer_GL3.h"
#include "document-model.h"
#include <SDL.h>
#include <SDL_image.h>
#include <lunasvg.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <memory>
#include <limits>
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
        if (Rml::StringUtilities::ToLower(std::filesystem::u8path(source).extension().string()) == ".svg") {
            auto svg = lunasvg::Document::loadFromFile(source);
            if (!svg) return 0;
            auto bitmap = svg->renderToBitmap();
            if (bitmap.isNull()) return 0;
            dimensions = {bitmap.width(), bitmap.height()};
            const size_t size = size_t(dimensions.x) * dimensions.y * 4;
            for (size_t i = 0; i < size; i += 4) std::swap(bitmap.data()[i], bitmap.data()[i+2]);
            return GenerateTexture({bitmap.data(), size}, dimensions);
        }
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
static std::string pending_target;
static std::string focused_target;
static bool initialized;
static std::vector<Rml::byte> font_data;
static std::vector<Rml::byte> bold_font_data;

class Actions final : public Rml::EventListener {
public:
    void ProcessEvent(Rml::Event& event) override {
        // Queue actions. Never destroy a document while RmlUi is dispatching an event.
        auto* element = event.GetTargetElement();
        while (element && !element->HasAttribute("action")) element = element->GetParentNode();
        if (element) {
            if (event.GetId() == Rml::EventId::Click)
            {
                pending_action = element->GetAttribute<Rml::String>("action", "");
                pending_target = element->GetAttribute<Rml::String>("target", "");
            }
            else {
                if (event.GetId() == Rml::EventId::Mouseover && context->GetFocusElement() != element)
                    element->Focus();
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
    for (const char* attribute : {"bind-text", "bind-lines", "bind-value"}) {
        const auto name = element->GetAttribute<Rml::String>(attribute, "");
        if (!name.empty()) bindings[name].push_back({element, attribute});
    }
    if (element->HasAttribute("action")) {
        controls.push_back(element);
    }
    for (int i = 0; i < element->GetNumChildren(); ++i) bind_tree(element->GetChild(i));
}

UI_EXPORT const char* ui_error() { return last_error.c_str(); }
UI_EXPORT void ui_close_document() {
    bindings.clear(); controls.clear(); pending_action.clear(); pending_target.clear();
    if (document) { document->Close(); document = nullptr; context->Update(); }
}
UI_EXPORT void ui_shutdown() {
    if (!initialized) return;
    ui_close_document();
    Rml::Shutdown();
    DocumentModel::Reset();
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
    if (context && !DocumentModel::Initialize(context)) { last_error = "Data model initialization failed"; ui_shutdown(); return 0; }
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
    document->AddEventListener(Rml::EventId::Click, &actions);
    document->AddEventListener(Rml::EventId::Focus, &actions, true);
    document->AddEventListener(Rml::EventId::Mouseover, &actions);
    document->Show(); context->Update();
    if (!controls.empty()) controls.front()->Focus();
    return 1;
}
UI_EXPORT int ui_style(const char* filename) {
    if (!document || !filename) return 0;
    auto sheet = Rml::Factory::InstanceStyleSheetFile(filename);
    if (!sheet) { last_error = std::string("Cannot load frontend stylesheet: ") + filename; return 0; }
    if (const auto* current = document->GetStyleSheetContainer())
        sheet = current->CombineStyleSheetContainer(*sheet);
    document->SetStyleSheetContainer(std::move(sheet));
    context->Update();
    return 1;
}
UI_EXPORT void ui_set(const char* name, const char* value) {
    DocumentModel::Set(name, value);
    const auto found = bindings.find(name);
    if (found == bindings.end()) return; // Optional elements need no game-side defaults.
    for (const auto& binding : found->second) {
        if (binding.attribute == "bind-lines") {
            auto markup = Rml::StringUtilities::EncodeRml(value);
            size_t position = 0;
            while ((position = markup.find('\n', position)) != Rml::String::npos) {
                markup.replace(position, 1, "<br/>"); position += 5;
            }
            binding.element->SetInnerRML(markup);
        }
        else if (binding.attribute == "bind-text") binding.element->SetInnerRML(Rml::StringUtilities::EncodeRml(value));
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
UI_EXPORT const char* ui_action_target() { return pending_target.c_str(); }
UI_EXPORT const char* ui_focused_target() {
    auto* element = context ? context->GetFocusElement() : nullptr;
    focused_target = element ? element->GetAttribute<Rml::String>("focus-target", element->GetAttribute<Rml::String>("target", "")) : "";
    return focused_target.c_str();
}
UI_EXPORT void ui_clear_action() { pending_action.clear(); pending_target.clear(); }
UI_EXPORT void ui_model_set(const char* name, const char* value, int type) { DocumentModel::Set(name, value, type); }
UI_EXPORT void ui_model_array(const char* name, int count) { DocumentModel::Array(name, count); }
UI_EXPORT void ui_focus(const char* id) {
    if (!document) return;
    context->Update();
    if (auto* element = document->GetElementById(id)) {
        if (context->GetFocusElement() == element) return;
        element->Focus();
        element->ScrollIntoView({Rml::ScrollAlignment::Nearest, Rml::ScrollAlignment::Nearest});
    }
}
UI_EXPORT void ui_reveal(const char* id) {
    if (!document) return;
    context->Update();
    if (auto* element = document->GetElementById(id)) {
        Rml::ScrollIntoViewOptions options;
        options.vertical = options.horizontal = Rml::ScrollAlignment::Nearest;
        options.parentage = Rml::ScrollParentage::Closest;
        element->ScrollIntoView(options);
    }
}
UI_EXPORT void ui_mouse(int x, int y, int button, int down) {
    if (!document) return;
    context->ProcessMouseMove(x, y, 0);
    if (button >= 0) {
        if (down) context->ProcessMouseButtonDown(button, 0);
        else context->ProcessMouseButtonUp(button, 0);
    }
}
UI_EXPORT int ui_bounds(const char* id, float* x, float* y, float* width, float* height) {
    if (!document || !id || !x || !y || !width || !height) return 0;
    context->Update();
    auto* element = document->GetElementById(id);
    if (!element || !element->IsVisible(true)) return 0;
    const auto offset = element->GetAbsoluteOffset(Rml::BoxArea::Content);
    const auto size = element->GetBox().GetSize(Rml::BoxArea::Content);
    *x = offset.x; *y = offset.y; *width = size.x; *height = size.y;
    return size.x > 0 && size.y > 0;
}
UI_EXPORT void ui_scroll(float delta) {
    if (context) context->ProcessMouseWheel(delta, 0);
}
UI_EXPORT void ui_key(int key) {
    if (!document) return;
    // Navigate actual document geometry, independent of screen roles or button counts.
    context->Update();
    controls.clear(); document->QuerySelectorAll(controls, "[action]");
    if (controls.empty()) return;
    auto it = std::find(controls.begin(), controls.end(), context->GetFocusElement());
    int index = it == controls.end() ? 0 : int(it - controls.begin());
    if (key != 0) {
        const bool vertical = std::abs(key) == 2;
        const int direction = key > 0 ? 1 : -1;
        const auto center = [](Rml::Element* e) {
            return e->GetAbsoluteOffset(Rml::BoxArea::Border) + e->GetBox().GetSize(Rml::BoxArea::Border) * 0.5f;
        };
        const auto from = center(controls[index]);
        float best = std::numeric_limits<float>::max();
        Rml::Element* next = nullptr;
        for (auto* candidate : controls) {
            if (candidate == controls[index] || !candidate->IsVisible(true) || candidate->HasAttribute("disabled")) continue;
            const auto delta = center(candidate) - from;
            const float forward = (vertical ? delta.y : delta.x) * direction;
            if (forward < 1) continue;
            const float sideways = vertical ? delta.x : delta.y;
            const float score = forward * forward + 4 * sideways * sideways;
            if (score < best) { best = score; next = candidate; }
        }
        if (next) next->Focus();
    } else if (key == 0) {
        pending_action = controls[index]->GetAttribute<Rml::String>("action", "");
        pending_target = controls[index]->GetAttribute<Rml::String>("target", "");
    }
}
