// SPDX-License-Identifier: GPL-2.0-or-later
// The C boundary keeps RmlUi's C++ objects out of the Pascal game.
#include <RmlUi/Core.h>
#include <RmlUi/Core/Factory.h>
#include <RmlUi/Core/StyleSheetContainer.h>
#include "RmlUi_Renderer_GL3.h"
#include "document-model.h"
#include "document-table.h"
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
#include <cstdint>

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
struct Binding { Rml::Element* element; std::string attribute; };
struct DocumentState;
class Actions final : public Rml::EventListener {
    DocumentState* owner;
public:
    explicit Actions(DocumentState* state) : owner(state) {}
    void ProcessEvent(Rml::Event& event) override;
};
struct DocumentState {
    Rml::Context* context = nullptr;
    Rml::ElementDocument* document = nullptr;
    std::unordered_map<std::string, std::vector<Binding>> bindings;
    std::vector<Rml::Element*> controls;
    std::string pending_action, pending_target, focused_target;
    bool text_fit_dirty = true, table_layout_dirty = true;
    int last_width = 0, last_height = 0;
    Actions actions{this};
};
static DocumentState fallback;
static DocumentState* active = &fallback;
static std::unordered_map<uint64_t, std::unique_ptr<DocumentState>> documents;
static uint64_t next_document_id = 1;
static bool pointer_known = false;
static int pointer_x = 0, pointer_y = 0;
static bool initialized;
static void update_document_layout();
static std::vector<Rml::byte> font_data, bold_font_data;
void Actions::ProcessEvent(Rml::Event& event) {
        // Queue actions. Never destroy a document while RmlUi is dispatching an event.
        auto* element = event.GetTargetElement();
        while (element && !element->HasAttribute("action")) element = element->GetParentNode();
        if (element) {
            if (event.GetId() == Rml::EventId::Click)
            {
                owner->pending_action = element->GetAttribute<Rml::String>("action", "");
                owner->pending_target = element->GetAttribute<Rml::String>("target", "");
            }
            else {
                const auto target = element->GetAttribute<Rml::String>("focus-text-target", "");
                const auto key = element->GetAttribute<Rml::String>("focus-text-lang", "");
                if (owner->document && !target.empty()) {
                    if (auto* label = owner->document->GetElementById(target))
                        label->SetInnerRML(Rml::StringUtilities::EncodeRml(translate ? translate(key.c_str()) : key));
                }
            }
        }
}

static void bind_tree(Rml::Element* element) {
    const auto key = element->GetAttribute<Rml::String>("lang", "");
    if (!key.empty()) {
        // SetInnerRML parses markup: translations must be escaped as plain text.
        element->SetInnerRML(Rml::StringUtilities::EncodeRml(translate ? translate(key.c_str()) : key));
    }
    for (const char* attribute : {"bind-text", "bind-lines", "bind-emphasis", "bind-value"}) {
        const auto name = element->GetAttribute<Rml::String>(attribute, "");
        if (!name.empty()) active->bindings[name].push_back({element, attribute});
    }
    if (element->HasAttribute("action")) {
        active->controls.push_back(element);
    }
    for (int i = 0; i < element->GetNumChildren(); ++i) bind_tree(element->GetChild(i));
}

UI_EXPORT const char* ui_error() { return last_error.c_str(); }
UI_EXPORT void ui_close_document() {
    DocumentTables::ClearCache(); active->table_layout_dirty = true;
    active->bindings.clear(); active->controls.clear(); active->pending_action.clear(); active->pending_target.clear();
    if (active->document) { active->document->Close(); active->document = nullptr; active->context->Update(); }
}
static bool create_context(uint64_t id) {
    auto state = std::make_unique<DocumentState>();
    const auto name = "usce-" + std::to_string(id);
    state->context = Rml::CreateContext(name, {800, 600});
    if (!state->context) return false;
    if (!DocumentModel::Initialize(state->context)) {
        Rml::RemoveContext(name);
        DocumentModel::Release(state->context);
        return false;
    }
    active = state.get();
    documents[id] = std::move(state);
    return true;
}
UI_EXPORT int ui_select(uint64_t id) {
    const auto found = documents.find(id);
    if (found == documents.end()) return 0;
    active = found->second.get();
    DocumentModel::Select(active->context);
    return 1;
}
UI_EXPORT void ui_destroy(uint64_t id) {
    const auto found = documents.find(id);
    if (id == 0 || found == documents.end()) return;
    auto* previous = active;
    active = found->second.get();
    ui_close_document();
    auto* context = active->context;
    Rml::RemoveContext(context->GetName());
    DocumentModel::Release(context);
    if (previous == active) previous = documents.at(0).get();
    documents.erase(found);
    active = previous;
    DocumentModel::Select(active->context);
}
UI_EXPORT void ui_shutdown() {
    if (!initialized) return;
    for (auto& pair : documents) {
        active = pair.second.get();
        ui_close_document();
        Rml::RemoveContext(active->context->GetName());
        DocumentModel::Release(active->context);
    }
    documents.clear(); active = &fallback;
    Rml::Shutdown(); DocumentModel::Reset();
    renderer.reset(); font_data.clear(); bold_font_data.clear(); RmlGL3::Shutdown(); initialized = false;
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
    pointer_known = false;
    if (!create_context(0)) { last_error = "Data model initialization failed"; ui_shutdown(); return 0; }
    std::ifstream file(std::filesystem::u8path(font), std::ios::binary);
    font_data.assign(std::istreambuf_iterator<char>(file), {});
    if (!active->context || font_data.empty() || !Rml::LoadFontFace(font_data, "ui", Rml::Style::FontStyle::Normal)) {
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
    active->text_fit_dirty = true;
    active->document = active->context->LoadDocument(filename);
    if (!active->document) { last_error = std::string("Cannot load frontend document: ") + filename; return 0; }
    bind_tree(active->document);
    active->document->AddEventListener(Rml::EventId::Click, &active->actions);
    active->document->AddEventListener(Rml::EventId::Focus, &active->actions, true);
    active->document->Show(); active->context->Update();
    if (!active->controls.empty()) active->controls.front()->Focus();
    return 1;
}
UI_EXPORT uint64_t ui_create(const char* filename, const char* array_binding) {
    if (!initialized || !filename) return 0;
    auto* previous = active;
    const auto id = next_document_id++;
    if (!create_context(id)) { active = previous; DocumentModel::Select(active->context); return 0; }
    if (array_binding && *array_binding) DocumentModel::Array(array_binding, 0);
    if (!ui_open(filename)) { ui_destroy(id); active = previous; DocumentModel::Select(active->context); return 0; }
    return id;
}
UI_EXPORT int ui_style(const char* filename) {
    if (!active->document || !filename) return 0;
    auto sheet = Rml::Factory::InstanceStyleSheetFile(filename);
    if (!sheet) { last_error = std::string("Cannot load frontend stylesheet: ") + filename; return 0; }
    if (const auto* current = active->document->GetStyleSheetContainer())
        sheet = current->CombineStyleSheetContainer(*sheet);
    active->text_fit_dirty = true; active->table_layout_dirty = true; DocumentTables::ClearCache();
    active->document->SetStyleSheetContainer(std::move(sheet));
    active->context->Update();
    return 1;
}
UI_EXPORT void ui_set(const char* name, const char* value) {
    if (DocumentModel::Set(name, value)) active->table_layout_dirty = true;
    const auto found = active->bindings.find(name);
    if (found == active->bindings.end()) return; // Optional elements need no game-side defaults.
    active->text_fit_dirty = true; active->table_layout_dirty = true;
    for (const auto& binding : found->second) {
        if (binding.attribute == "bind-emphasis") {
            // Only line breaks and paired emphasis markers are interpreted.
            // Escape metadata and translations before introducing any markup.
            const auto escaped = Rml::StringUtilities::EncodeRml(value);
            Rml::String markup;
            bool bold = false;
            for (size_t i = 0; i < escaped.size(); ++i) {
                if (escaped[i] == '\n') markup += "<br/>";
                else if (escaped[i] == '*' && i + 1 < escaped.size() && escaped[i+1] == '*') {
                    markup += bold ? "</b>" : "<b>"; bold = !bold; ++i;
                } else markup += escaped[i];
            }
            if (bold) markup += "</b>";
            binding.element->SetInnerRML(markup);
            active->text_fit_dirty = true;
        }
        else if (binding.attribute == "bind-lines") {
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
static void fit_text() {
    std::vector<Rml::Element*> elements;
    active->document->QuerySelectorAll(elements, "[fit-text]");
    for (auto* element : elements) element->RemoveProperty(Rml::PropertyId::FontSize);
    active->context->Update();
    for (auto* element : elements) {
        const float maximum = element->GetComputedValues().font_size();
        float low = element->GetAttribute<float>("fit-text", 1.0f), high = maximum;
        const auto fits = [&]() { return element->GetScrollHeight() <= element->GetClientHeight() + 0.5f; };
        if (fits()) continue;
        for (int step = 0; step < 10 && high - low > 0.25f; ++step) {
            const float middle = (low + high) * 0.5f;
            element->SetProperty(Rml::PropertyId::FontSize, Rml::Property(middle, Rml::Unit::PX));
            active->context->Update();
            if (fits()) low = middle; else high = middle;
        }
        element->SetProperty(Rml::PropertyId::FontSize, Rml::Property(low, Rml::Unit::PX));
        active->context->Update();
    }
    active->text_fit_dirty = false;
}
// Repeated data views create elements after the document was opened. Translate
// those elements too, without rebuilding unchanged text on animation frames.
static void translate_dynamic_elements() {
    Rml::ElementList elements;
    active->document->QuerySelectorAll(elements, "[lang]");
    std::unordered_map<Rml::String, Rml::String> translations;
    for (auto* element : elements) {
        const auto key = element->GetAttribute<Rml::String>("lang", "");
        if (key.empty()) continue;
        auto result = translations.find(key);
        if (result == translations.end())
            result = translations.emplace(key, translate ? translate(key.c_str()) : key).first;
        const auto& value = result->second;
        if (!element->HasAttribute("translated-value") ||
            element->GetAttribute<Rml::String>("translated-value", "") != value) {
            element->SetInnerRML(Rml::StringUtilities::EncodeRml(value));
            element->SetAttribute("translated-value", value);
            active->text_fit_dirty = true;
        }
    }
}
static void update_document_layout() {
    active->context->Update();
    if (active->table_layout_dirty) {
        translate_dynamic_elements();
        active->context->Update();
    }
    if (active->text_fit_dirty) fit_text();
    if (active->table_layout_dirty) { DocumentTables::Layout(active->document, active->context); active->table_layout_dirty = false; }
}
UI_EXPORT void ui_render(int width, int height, int foreground_only) {
    if (!active->document || width <= 0 || height <= 0) return;
    active->document->SetClass("foreground-only", foreground_only == 1);
    active->document->SetClass("background-only", foreground_only == 2);
    if (width != active->last_width || height != active->last_height) { active->text_fit_dirty = true; active->table_layout_dirty = true; }
    active->last_width = width; active->last_height = height;
    active->context->SetDimensions({width, height}); update_document_layout();
    renderer->SetViewport(width, height);
    renderer->BeginFrame(); active->context->Render(); renderer->EndFrame();
}
UI_EXPORT const char* ui_action() { return active->pending_action.c_str(); }
UI_EXPORT const char* ui_action_target() { return active->pending_target.c_str(); }
UI_EXPORT const char* ui_focused_target() {
    auto* element = active->context ? active->context->GetFocusElement() : nullptr;
    active->focused_target = element ? element->GetAttribute<Rml::String>("focus-target", element->GetAttribute<Rml::String>("target", "")) : "";
    return active->focused_target.c_str();
}
UI_EXPORT void ui_clear_action() { active->pending_action.clear(); active->pending_target.clear(); }
UI_EXPORT void ui_model_set(const char* name, const char* value, int type) { if (DocumentModel::Set(name, value, type)) active->table_layout_dirty = true; }
UI_EXPORT void ui_model_array(const char* name, int count) { if (DocumentModel::Array(name, count)) active->table_layout_dirty = true; }
UI_EXPORT void ui_focus(const char* id) {
    if (!active->document) return;
    update_document_layout();
    if (auto* element = active->document->GetElementById(id)) {
        if (active->context->GetFocusElement() == element) return;
        element->Focus();
        element->ScrollIntoView({Rml::ScrollAlignment::Nearest, Rml::ScrollAlignment::Nearest});
    }
}
UI_EXPORT void ui_reveal(const char* id) {
    if (!active->document) return;
    update_document_layout();
    if (auto* element = active->document->GetElementById(id); element && element->IsVisible(true)) {
        Rml::ScrollIntoViewOptions options;
        options.horizontal = Rml::ScrollAlignment::Nearest;
        options.vertical = element->GetAttribute<Rml::String>("reveal-align", "") == "start" ?
            Rml::ScrollAlignment::Start : Rml::ScrollAlignment::Nearest;
        options.parentage = Rml::ScrollParentage::Closest;
        element->ScrollIntoView(options);
    }
}
UI_EXPORT void ui_mouse(int x, int y, int button, int down) {
    if (!active->document) return;
    update_document_layout();
    const bool moved = !pointer_known || x != pointer_x || y != pointer_y;
    pointer_known = true; pointer_x = x; pointer_y = y;
    if (moved || button >= 0) {
        active->context->ProcessMouseMove(x, y, 0);
        auto* hovered = active->context->GetHoverElement();
        while (hovered && !hovered->HasAttribute("action")) hovered = hovered->GetParentNode();
        if (hovered && !hovered->HasAttribute("disabled")) hovered->Focus();
    }
    if (button >= 0) {
        if (down) active->context->ProcessMouseButtonDown(button, 0);
        else active->context->ProcessMouseButtonUp(button, 0);
    }
}
UI_EXPORT int ui_bounds(const char* id, float* x, float* y, float* width, float* height) {
    if (!active->document || !id || !x || !y || !width || !height) return 0;
    update_document_layout();
    auto* element = active->document->GetElementById(id);
    if (!element || !element->IsVisible(true)) return 0;
    const auto offset = element->GetAbsoluteOffset(Rml::BoxArea::Content);
    const auto size = element->GetBox().GetSize(Rml::BoxArea::Content);
    *x = offset.x; *y = offset.y; *width = size.x; *height = size.y;
    return size.x > 0 && size.y > 0;
}
UI_EXPORT void ui_scroll(float delta) {
    if (active->context) active->context->ProcessMouseWheel(delta, 0);
}
UI_EXPORT void ui_key(int key) {
    if (!active->document) return;
    // Navigation uses document geometry or order, independent of screen roles or button counts.
    update_document_layout();
    active->controls.clear(); active->document->QuerySelectorAll(active->controls, "[action]");
    if (active->controls.empty()) return;
    auto it = std::find(active->controls.begin(), active->controls.end(), active->context->GetFocusElement());
    int index = it == active->controls.end() ? 0 : int(it - active->controls.begin());
    if (std::abs(key) == 3) {
        // Ordered form navigation follows document order, treating arrow controls
        // for the same field as one stop. Spatial navigation remains available.
        const auto group = [](Rml::Element* e) {
            return e->GetAttribute<Rml::String>("focus-target", e->GetAttribute<Rml::String>("target", ""));
        };
        const auto origin = group(active->controls[index]);
        const int direction = key > 0 ? 1 : -1;
        for (int step = 1; step <= int(active->controls.size()); ++step) {
            auto* candidate = active->controls[(index + int(active->controls.size()) + direction * step) % int(active->controls.size())];
            if (!candidate->IsVisible(true) || candidate->HasAttribute("disabled")) continue;
            if (!origin.empty() && group(candidate) == origin) continue;
            candidate->Focus();
            break;
        }
    } else if (key != 0) {
        const bool vertical = std::abs(key) == 2;
        const int direction = key > 0 ? 1 : -1;
        const auto center = [](Rml::Element* e) {
            return e->GetAbsoluteOffset(Rml::BoxArea::Border) + e->GetBox().GetSize(Rml::BoxArea::Border) * 0.5f;
        };
        const auto from = center(active->controls[index]);
        float best = std::numeric_limits<float>::max();
        Rml::Element* next = nullptr;
        for (auto* candidate : active->controls) {
            if (candidate == active->controls[index] || !candidate->IsVisible(true) || candidate->HasAttribute("disabled")) continue;
            if (!vertical) {
                const auto origin_top = active->controls[index]->GetAbsoluteOffset(Rml::BoxArea::Border).y;
                const auto origin_bottom = origin_top + active->controls[index]->GetBox().GetSize(Rml::BoxArea::Border).y;
                const auto target_top = candidate->GetAbsoluteOffset(Rml::BoxArea::Border).y;
                const auto target_bottom = target_top + candidate->GetBox().GetSize(Rml::BoxArea::Border).y;
                if (std::min(origin_bottom, target_bottom) <= std::max(origin_top, target_top)) continue;
            }
            const auto delta = center(candidate) - from;
            const float forward = (vertical ? delta.y : delta.x) * direction;
            if (forward < 1) continue;
            const float sideways = vertical ? delta.x : delta.y;
            const float score = forward * forward + 4 * sideways * sideways;
            if (score < best) { best = score; next = candidate; }
        }
        if (next) next->Focus();
    } else if (key == 0) {
        active->pending_action = active->controls[index]->GetAttribute<Rml::String>("action", "");
        active->pending_target = active->controls[index]->GetAttribute<Rml::String>("target", "");
    }
}
