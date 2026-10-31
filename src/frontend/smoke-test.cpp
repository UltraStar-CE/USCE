// SPDX-License-Identifier: GPL-2.0-or-later
#define SDL_MAIN_HANDLED
#include <SDL.h>
#define GLAD_GL_IMPLEMENTATION
#include "RmlUi_Include_GL3.h"
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

extern "C" {
int ui_initialize(const char* (*)(const char*), void (*)(int, const char*), const char*, const char*);
int ui_open(const char*);
void ui_set(const char*, const char*);
void ui_render(int, int, int);
void ui_mouse(int, int, int, int);
void ui_key(int);
int ui_bounds(const char*, float*, float*, float*, float*);
void ui_model_set(const char*, const char*, int);
void ui_model_array(const char*, int);
void ui_focus(const char*);
const char* ui_focused_target();
const char* ui_action_target();
const char* ui_action();
void ui_clear_action();
void ui_shutdown();
}
static void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
static const char* translate(const char* key) { return key; }
static int warnings = 0;
static void log(int level, const char* message) {
    if (level <= 3) { ++warnings; std::cerr << message << '\n'; }
}
static std::string utf8(const std::filesystem::path& path) {
    const auto text = path.u8string();
    return std::string(text.begin(), text.end());
}
int main(int argc, char** argv) {
    try {
        require(argc == 2, "Expected game asset directory");
        const auto root = std::filesystem::u8path(argv[1]);
        SDL_SetMainReady();
        require(SDL_Init(SDL_INIT_VIDEO) == 0, SDL_GetError());
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
        auto* window = SDL_CreateWindow("USCE frontend test", 0, 0, 1280, 720, SDL_WINDOW_OPENGL | SDL_WINDOW_HIDDEN);
        require(window != nullptr, SDL_GetError());
        const auto gl_context = SDL_GL_CreateContext(window);
        require(gl_context != nullptr, SDL_GetError());
        require(gladLoaderLoadGL() >= GLAD_MAKE_VERSION(3, 3), "OpenGL 3.3 required");
        const auto font = utf8(root / "fonts/NotoSans/GoNotoKurrent-Regular.ttf");
        const auto bold = utf8(root / "fonts/NotoSans/GoNotoKurrent-Bold.ttf");
        const auto main_document = utf8(root / "frontends/modern/main.rml");
        const auto loading_document = utf8(root / "frontends/modern/loading.rml");
        const auto settings_document = utf8(root / "frontends/modern/settings.rml");
        const auto form_document = utf8(root / "frontends/modern/settings-form.rml");
        for (int cycle = 0; cycle < 2; ++cycle) {
            require(ui_initialize(translate, log, font.c_str(), bold.c_str()) != 0, "Frontend initialization");
            require(ui_open(main_document.c_str()) != 0, "Main document");
            GLuint framebuffer, texture;
            glGenTextures(1, &texture); glBindTexture(GL_TEXTURE_2D, texture);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1280, 720, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
            glGenFramebuffers(1, &framebuffer); glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
            require(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "Test framebuffer");
            glViewport(0, 0, 1280, 720);
            glClearColor(0, 0, 0, 0); glClear(GL_COLOR_BUFFER_BIT);
            ui_render(1280, 720, 0);
            GLint bound = 0; glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &bound);
            require(GLuint(bound) == framebuffer, "Frontend changed the game's render target");
            unsigned char pixel[4] = {};
            glReadPixels(200, 720-350, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[1] > 80 && pixel[2] > 80 && pixel[3] > 240, "UI missing from transition texture");
            const int button_red = pixel[0], button_green = pixel[1], button_blue = pixel[2];
            glClear(GL_COLOR_BUFFER_BIT);
            ui_render(1280, 720, 2);
            glReadPixels(200, 720-350, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[3] > 240 && std::abs(int(pixel[0])-button_red) + std::abs(int(pixel[1])-button_green) + std::abs(int(pixel[2])-button_blue) > 20,
                "Background-only pass contains menu buttons");
            glClear(GL_COLOR_BUFFER_BIT);
            ui_render(1280, 720, 1);
            glReadPixels(640, 720-420, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[3] == 0, "Background leaked into foreground transition capture");
            glReadPixels(200, 720-350, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[3] > 200, "Foreground transition capture lost buttons");
            ui_mouse(200, 350, 0, 1); ui_mouse(200, 350, 0, 0);
            require(std::string(ui_action()) == "game.sing", "Named mouse action");
            ui_clear_action(); ui_key(1); ui_key(0);
            require(std::string(ui_action()) == "game.party", "Document-order keyboard action");
            require(ui_open(settings_document.c_str()) != 0, "Settings document");
            ui_render(1280, 720, 0);
            ui_key(2); ui_key(0);
            require(std::string(ui_action()) == "settings.lyrics.open", "Spatial down navigation");
            ui_clear_action(); ui_key(1); ui_key(0);
            require(std::string(ui_action()) == "settings.themes.open", "Spatial right navigation");
            ui_mouse(1040, 612, 0, 1); ui_mouse(1040, 612, 0, 0);
            require(std::string(ui_action()) == "navigation.back", "Settings back action");
            require(ui_open(loading_document.c_str()) != 0, "Loading document");
            ui_set("loading.status", "<plain text> & progress");
            ui_set("loading.progress", "0.5");
            ui_set("optional.missing", "ignored");
            ui_render(1280, 720, 0); ui_render(1680, 720, 0);
            ui_model_array("form.fields", 2);
            for (int index = 0; index < 2; ++index) {
                const auto prefix = "form.fields[" + std::to_string(index) + "].";
                ui_model_set((prefix+"id").c_str(), std::to_string(index).c_str(), 1);
                ui_model_set((prefix+"label").c_str(), "Test option", 0);
                ui_model_set((prefix+"value").c_str(), "Value", 0);
                ui_model_set((prefix+"kind").c_str(), "0", 1);
                ui_model_set((prefix+"selected").c_str(), index == 0 ? "1" : "0", 2);
                ui_model_set((prefix+"previous").c_str(), "0", 2);
                ui_model_set((prefix+"next").c_str(), "1", 2);
            }
            require(ui_open(form_document.c_str()) != 0, "Repeated form document");
            ui_render(1280, 720, 0);
            ui_focus("field-0");
            require(std::string(ui_focused_target()) == "0", "Repeated field binding");
            ui_mouse(1152, 177, 0, 1); ui_mouse(1152, 177, 0, 0);
            require(std::string(ui_action()) == "form.increment" && std::string(ui_action_target()) == "0", "Repeated field action argument");
            ui_clear_action();
            ui_model_array("form.fields", 1);
            ui_model_set("form.fields[0].label", "Changed <label> & value", 0);
            ui_render(1280, 720, 0);
            ui_focus("field-0");
            ui_key(0);
            require(std::string(ui_action()) == "form.activate" && std::string(ui_action_target()) == "0", "Collection resize preserved surviving field actions");
            ui_clear_action();
            ui_model_array("form.fields", 0);
            ui_render(1280, 720, 0);
            ui_focus("form-back"); ui_key(0);
            require(std::string(ui_action()) == "navigation.back", "Empty collection preserved document controls");
            const auto lyrics_document = utf8(root / "frontends/modern/settings-lyrics.rml");
            require(ui_open(lyrics_document.c_str()) != 0, "Lyrics document");
            ui_render(1280, 720, 0);
            float x, y, width, height;
            require(ui_bounds("lyrics-preview-0", &x, &y, &width, &height) != 0, "Native preview region");
            require(std::abs(x - 128) < 1 && std::abs(y - 420) < 1 && std::abs(width - 1024) < 1 && std::abs(height - 48) < 1, "Theme-defined preview geometry");
            ui_render(1024, 768, 0);
            require(ui_bounds("lyrics-preview-0", &x, &y, &width, &height) != 0 && std::abs(width - 819.2f) < 1 && std::abs(height - 51.2f) < 1, "Preview geometry follows theme resizing");
            require(ui_bounds("missing-region", &x, &y, &width, &height) == 0, "Missing preview region is optional");
            ui_model_array("form.fields", 1);
            ui_model_set("form.fields[0].id", "0", 1);
            ui_model_set("form.fields[0].label", "Camera", 0);
            ui_model_set("form.fields[0].value", "Off", 0);
            ui_model_set("form.fields[0].kind", "0", 1);
            ui_model_set("form.fields[0].selected", "1", 2);
            ui_model_set("form.fields[0].previous", "0", 2);
            ui_model_set("form.fields[0].next", "1", 2);
            const auto webcam_document = utf8(root / "frontends/modern/settings-webcam.rml");
            require(ui_open(webcam_document.c_str()) != 0, "Webcam document");
            ui_model_set("form.preview", "1", 2);
            glClear(GL_COLOR_BUFFER_BIT);
            ui_render(1280, 720, 1);
            glReadPixels(300, 720-180, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[3] > 80 && pixel[3] < 150, "Theme dims controls during camera preview");
            ui_model_set("form.preview", "0", 2);
            glClear(GL_COLOR_BUFFER_BIT); ui_render(1280, 720, 1);
            glReadPixels(300, 720-180, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[3] > 200, "Leaving camera preview restores control opacity");
            require(ui_bounds("webcam-preview", &x, &y, &width, &height) != 0 && width == 1280 && height == 720, "Theme-defined webcam surface");
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glDeleteFramebuffers(1, &framebuffer); glDeleteTextures(1, &texture);
            ui_shutdown();
        }
        SDL_GL_DeleteContext(gl_context); SDL_DestroyWindow(window); SDL_Quit();
        require(warnings == 0, "Frontend emitted parser or binding diagnostics");
        std::cout << "Frontend lifecycle, bindings, input, resizing and transition capture passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
