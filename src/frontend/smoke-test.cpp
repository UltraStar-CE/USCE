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
int ui_style(const char*);
void ui_set(const char*, const char*);
void ui_render(int, int, int);
void ui_mouse(int, int, int, int);
void ui_key(int);
int ui_bounds(const char*, float*, float*, float*, float*);
void ui_model_set(const char*, const char*, int);
void ui_model_array(const char*, int);
void ui_focus(const char*);
void ui_reveal(const char*);
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
                ui_model_set((prefix+"visible").c_str(), "1", 2);
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
            ui_model_set("form.fields[0].visible", "1", 2);
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
            ui_model_array("form.fields", 2);
            ui_model_set("form.fields[1].id", "1", 1);
            ui_model_set("form.fields[1].label", "Input source", 0);
            ui_model_set("form.fields[1].value", "Microphone", 0);
            ui_model_set("form.fields[1].kind", "0", 1);
            ui_model_set("form.fields[1].visible", "1", 2);
            ui_model_set("form.fields[1].selected", "0", 2);
            ui_model_set("form.fields[1].previous", "0", 2);
            ui_model_set("form.fields[1].next", "0", 2);
            ui_model_set("form.fields[0].inline", "1", 2);
            ui_model_array("form.fields[0].choices", 25);
            for (int option = 0; option < 25; ++option) {
                const auto prefix = "form.fields[0].choices[" + std::to_string(option) + "].";
                ui_model_set((prefix+"id").c_str(), ("choice-0-" + std::to_string(option)).c_str(), 0);
                ui_model_set((prefix+"label").c_str(), std::to_string(option).c_str(), 0);
                ui_model_set((prefix+"target").c_str(), ("0:" + std::to_string(option)).c_str(), 0);
                ui_model_set((prefix+"selected").c_str(), option == 0 ? "1" : "0", 2);
            }
            const auto recording_document = utf8(root / "frontends/modern/settings-recording.rml");
            require(ui_open(recording_document.c_str()) != 0, "Microphone document");
            ui_render(1280, 720, 0);
            ui_clear_action();
            ui_mouse(665, 177, 0, 1); ui_mouse(665, 177, 0, 0);
            require(std::string(ui_action()) == "form.choose" && std::string(ui_action_target()) == "0:1", "Inline choice preserves its field and value");
            ui_reveal("choice-0-24"); ui_render(1280, 720, 0);
            require(ui_bounds("choice-0-24", &x, &y, &width, &height) != 0 && x >= 528 && x + width <= 1169, "Last player choice scrolls into the theme viewport");
            ui_clear_action();
            ui_mouse(int(x + width/2), int(y + height/2), 0, 1); ui_mouse(int(x + width/2), int(y + height/2), 0, 0);
            require(std::string(ui_action_target()) == "0:24", "Last player remains clickable");
            require(ui_bounds("field-surface-1", &x, &y, &width, &height) != 0, "Microphone meter surface");
            require(std::abs(x - 528) < 1 && std::abs(y - 247.2f) < 1 && std::abs(width - 640) < 1 && std::abs(height - 13.2f) < 1, "Microphone meter follows its field geometry");
            ui_model_array("form.commands", 1);
            ui_model_set("form.commands[0].id", "9", 1);
            ui_model_set("form.commands[0].label", "Add account", 0);
            ui_model_set("form.commands[0].selected", "0", 2);
            ui_model_set("form.notice", "Add an account to configure scores", 0);
            const auto network_document = utf8(root / "frontends/modern/settings-network.rml");
            require(ui_open(network_document.c_str()) != 0, "Network document");
            ui_render(1280, 720, 0); ui_clear_action();
            float back_x, back_y, back_width, back_height;
            require(ui_bounds("form-back", &back_x, &back_y, &back_width, &back_height) != 0, "Form back geometry");
            require(ui_bounds("command-9", &x, &y, &width, &height) != 0 && std::abs(y - back_y) < 1 && std::abs(x - 880) < 1, "Footer command sits beside Back");
            require(ui_bounds("form-back-reflection", &x, &y, &width, &height) != 0, "Back reflection geometry");
            if (std::abs(y - back_y - back_height - 2) >= 1) std::cerr << "reflection y " << y << " back " << back_y << " height " << back_height << '\n';
            require(std::abs(y - back_y - back_height - 2) < 1 && height > 19, "Reflection follows the Back button");
            glClear(GL_COLOR_BUFFER_BIT); ui_render(1280, 720, 1);
            glReadPixels(int(x + width/2), 720 - int(y + 2), 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[3] > 60 && pixel[3] < 170, "Back reflection renders its fading gradient");
            ui_focus("command-9"); ui_key(0);
            require(std::string(ui_action()) == "form.activate" && std::string(ui_action_target()) == "9", "Additional footer command keeps its interaction ID");
            const auto about_document = utf8(root / "frontends/modern/about.rml");
            require(ui_open(about_document.c_str()) != 0, "About document");
            ui_set("about.text", "Overview <plain text>\nSecond paragraph");
            ui_render(1280, 720, 0);
            ui_clear_action(); ui_key(2); ui_key(0);
            require(std::string(ui_action()) == "navigation.back", "About spatial navigation");
            ui_clear_action();
            ui_mouse(1100, 530, 0, 1); ui_mouse(1100, 530, 0, 0);
            require(std::string(ui_action()) == "credits.open", "About credits action");
            for (const char* variant : {"blue", "green", "pink", "red", "violet", "orange", "yellow", "brown", "black"}) {
                require(ui_open(main_document.c_str()) != 0, "Color variant document");
                const auto sheet = utf8(root / "frontends/modern/colors" / (std::string(variant) + ".rcss"));
                require(ui_style(sheet.c_str()) != 0, "Theme stylesheet overlay");
                ui_render(1280, 720, 0);
                if (std::string(variant) == "green") {
                    glReadPixels(200, 720-350, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
                    require(pixel[1] > pixel[0] + 30 && pixel[1] > pixel[2] + 20, "Theme stylesheet changes selected control color");
                }
            }
            require(ui_open(main_document.c_str()) != 0, "Skin variant document");
            ui_render(1280, 720, 0);
            unsigned char blue_background[4];
            glReadPixels(640, 720-420, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, blue_background);
            const auto winter_sheet = utf8(root / "frontends/modern/skins/winter.rcss");
            require(ui_style(winter_sheet.c_str()) != 0, "Winter skin stylesheet");
            ui_render(1280, 720, 0);
            glReadPixels(640, 720-420, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(std::abs(int(pixel[0])-blue_background[0]) + std::abs(int(pixel[1])-blue_background[1]) + std::abs(int(pixel[2])-blue_background[2]) > 40, "Skin stylesheet changes artwork");
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
