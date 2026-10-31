// SPDX-License-Identifier: GPL-2.0-or-later
#define SDL_MAIN_HANDLED
#include <SDL.h>
#define GLAD_GL_IMPLEMENTATION
#include "RmlUi_Include_GL3.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <cstdint>

extern "C" {
int ui_initialize(const char* (*)(const char*), void (*)(int, const char*), const char*, const char*);
int ui_open(const char*);
uint64_t ui_create(const char*, const char*);
int ui_select(uint64_t);
void ui_destroy(uint64_t);
int ui_style(const char*);
void ui_set(const char*, const char*);
void ui_render(int, int, int);
void ui_prepare(int, int);
void ui_scroll_to(const char*, float);
float ui_scroll_position(const char*);
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
static const char* translate(const char* key) { return std::string(key) == "REPEATED_TEST" ? "A translated repeated label" : key; }
static int warnings = 0;
static void log(int level, const char* message) {
    if (level <= 3) { ++warnings; std::cerr << message << '\n'; }
}
static std::string utf8(const std::filesystem::path& path) {
    const auto text = path.generic_u8string();
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
            const auto expect_action = [](const char* expected, const char* message) {
                ui_key(0); require(std::string(ui_action()) == expected, message); ui_clear_action();
            };
            ui_mouse(200, 350, -1, 0);
            ui_render(1280, 720, 0);
            expect_action("game.party", "Stationary pointer must not undo keyboard selection");
            glReadPixels(200, 720-350, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[0] + 10 < button_red, "Stationary hover must not leave a second highlighted button");
            ui_mouse(201, 351, -1, 0);
            expect_action("game.sing", "Moving pointer can select a button again");
            ui_focus("menu-sing");
            ui_key(1); ui_key(1); ui_key(1);
            expect_action("settings.open", "Right navigates across the main row");
            ui_key(1);
            expect_action("settings.open", "Right must not jump diagonally to Exit");
            ui_key(2);
            expect_action("game.exit", "Down reaches the aligned lower row");
            ui_key(-1);
            expect_action("about.open", "Left moves within the lower row");
            ui_key(-1);
            expect_action("about.open", "Left must not jump diagonally to a different row");
            ui_key(1); ui_key(-2);
            expect_action("settings.open", "Up returns to the aligned main button");
            ui_key(-1);
            expect_action("statistics.open", "Left returns along the main row");
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
            for (const auto* screen : {"party-options.rml", "tournament-options.rml"}) {
                const auto party_document = utf8(root / "frontends/modern" / screen);
                require(ui_open(party_document.c_str()) != 0, "Party options document");
                ui_render(1280, 720, 0);
                float party_x, party_y, party_w, party_h;
                require(ui_bounds("form-row-0", &party_x, &party_y, &party_w, &party_h) != 0 &&
                    std::abs(party_x - 112) < 1 && std::abs(party_y - 132) < 1 &&
                    std::abs(party_w - 1024) < 1 && std::abs(party_h - 48) < 1,
                    "Party fields must retain their theme-defined position and size");
                ui_mouse(1120, 156, 0, 1); ui_mouse(1120, 156, 0, 0);
                require(std::string(ui_action()) == "form.increment" && std::string(ui_action_target()) == "0",
                    "Party fields must reuse the named form actions");
                ui_clear_action();
            }
            // Nested choices must disappear before their now-invalid bindings update.
            ui_model_set("form.fields[0].inline", "1", 2);
            ui_model_array("form.fields[0].choices", 3);
            for (int i = 0; i < 3; ++i) {
                const auto prefix = "form.fields[0].choices[" + std::to_string(i) + "].";
                ui_model_set((prefix + "id").c_str(), ("nested-" + std::to_string(i)).c_str(), 0);
                ui_model_set((prefix + "target").c_str(), ("0:" + std::to_string(i)).c_str(), 0);
                ui_model_set((prefix + "label").c_str(), "Choice", 0);
                ui_model_set((prefix + "selected").c_str(), i == 0 ? "1" : "0", 2);
            }
            require(ui_open(form_document.c_str()) != 0, "Nested form choices");
            ui_render(1280, 720, 0);
            const int before_shrink = warnings;
            ui_model_array("form.fields[0].choices", 1);
            ui_render(1280, 720, 0);
            require(warnings == before_shrink, "Nested array shrink must not evaluate removed choice bindings");
            ui_model_set("form.fields[0].inline", "0", 2);
            require(ui_open(utf8(root / "frontends/modern/statistics.rml").c_str()) != 0, "Statistics overview document");
            std::string overview = "**Library**: <button id='injected' action='unexpected'>plain metadata</button>\n\n";
            for (int line = 0; line < 35; ++line) overview += "**Player** has a score on a long artist and song title.\n";
            ui_set("statistics.overview", overview.c_str());
            ui_render(1280, 720, 0); ui_render(1680, 720, 0); ui_render(1024, 768, 0);
            float stats_x, stats_y, stats_w, stats_h;
            require(!ui_bounds("injected", &stats_x, &stats_y, &stats_w, &stats_h), "Emphasis binding must escape embedded markup");
            ui_render(1280, 720, 0);
            ui_mouse(1088, 222, 0, 1); ui_mouse(1088, 222, 0, 0);
            require(std::string(ui_action()) == "statistics.detail.open" && std::string(ui_action_target()) == "1",
                "Statistics buttons use named detail actions");
            ui_clear_action();
            ui_model_set("statisticsDetail.kind", "1", 1);
            ui_model_set("statisticsDetail.pageSize", "30", 1);
            ui_model_array("statisticsDetail.columns", 4);
            const char* table_headers[] = {"#", "Player", "Avg. score", "Scores"};
            for (int column = 0; column < 4; ++column) {
                const auto prefix = "statisticsDetail.columns[" + std::to_string(column) + "].";
                ui_model_set((prefix + "id").c_str(), std::to_string(column).c_str(), 1);
                ui_model_set((prefix + "header").c_str(), table_headers[column], 0);
                ui_model_set((prefix + "numeric").c_str(), column == 1 ? "0" : "1", 2);
                ui_model_set((prefix + "flexible").c_str(), column == 1 ? "1" : "0", 2);
            }
            const auto populate_table = [](int count, bool long_names) {
                ui_model_array("statisticsDetail.rows", count);
                for (int row = 0; row < count; ++row) {
                    const auto prefix = "statisticsDetail.rows[" + std::to_string(row) + "].cells";
                    ui_model_array(prefix.c_str(), 4);
                    for (int column = 0; column < 4; ++column) {
                        const auto cell = prefix + "[" + std::to_string(column) + "].";
                        ui_model_set((cell + "id").c_str(), std::to_string(column).c_str(), 1);
                        const std::string value = column == 1 ? (long_names ? std::string(160, 'W') : "Ari") : std::to_string(column == 0 ? row + 1 : 9000);
                        ui_model_set((cell + "value").c_str(), value.c_str(), 0);
                        ui_model_set((cell + "numeric").c_str(), column == 1 ? "0" : "1", 2);
                    }
                }
            };
            populate_table(30, false);
            require(ui_open(utf8(root / "frontends/modern/statistics-detail.rml").c_str()) != 0, "Statistics table document");
            ui_render(1280, 720, 0);
            require(ui_bounds("statistics-detail-right", &stats_x, &stats_y, &stats_w, &stats_h), "Short statistics rows should use two measured tables");
            populate_table(5, false);
            require(!ui_bounds("statistics-detail-right", &stats_x, &stats_y, &stats_w, &stats_h), "Bounds queries must update split state after shrinking rows");
            populate_table(30, true);
            ui_model_set("statisticsDetail.kind", "2", 1);
            ui_render(1280, 720, 0);
            require(!ui_bounds("statistics-detail-right", &stats_x, &stats_y, &stats_w, &stats_h), "Long song rows must not be forced into narrow columns");
            ui_render(1680, 720, 0); ui_render(1024, 768, 0);
            ui_model_set("participants.count", "2", 1);
            ui_model_set("participants.focus", "-1", 1);
            ui_model_set("participants.previousCount", "0", 2);
            ui_model_set("participants.nextCount", "1", 2);
            ui_model_array("participants.fields", 16);
            for (int i = 0; i < 16; ++i) {
                const auto prefix = "participants.fields[" + std::to_string(i) + "].";
                ui_model_set((prefix + "id").c_str(), std::to_string(i).c_str(), 1);
                ui_model_set((prefix + "visible").c_str(), i < 2 ? "1" : "0", 2);
                ui_model_set((prefix + "value").c_str(), "Participant", 0);
                ui_model_set((prefix + "suffix").c_str(), "", 0);
            }
            require(ui_open(utf8(root / "frontends/modern/tournament-players.rml").c_str()) != 0,
                "Tournament participant document");
            ui_render(1280, 720, 0);
            ui_focus("participants-count");
            ui_key(3);
            require(std::string(ui_focused_target()) == "0", "Ordered navigation skips count arrows");
            ui_key(3);
            require(std::string(ui_focused_target()) == "1", "Ordered navigation follows participant order");
            ui_key(3);
            require(std::string(ui_focused_target()) == "count", "Ordered navigation skips hidden participants and wraps");
            ui_key(-3);
            require(std::string(ui_focused_target()) == "1", "Reverse ordered navigation wraps");
            ui_model_set("participants.fields[15].visible", "1", 2);
            ui_render(1280, 720, 0);
            ui_focus("participant-1");
            ui_key(3);
            require(std::string(ui_focused_target()) == "15", "Ordered navigation respects changing visibility");
            for (int i = 0; i < 16; ++i)
                ui_model_set(("participants.fields[" + std::to_string(i) + "].visible").c_str(), "1", 2);
            ui_render(1280, 720, 0);
            ui_mouse(1048, 570, 0, 1); ui_mouse(1048, 570, 0, 0);
            require(std::string(ui_action()) == "participants.select" && std::string(ui_action_target()) == "15",
                "Last participant has a theme-defined mouse target");
            ui_clear_action();
            require(ui_open(form_document.c_str()) != 0, "Return to settings form document");
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
            ui_model_set("players.count", "24", 1);
            ui_model_set("players.countLabel", "24", 0);
            ui_model_set("players.active", "1", 2);
            ui_model_set("players.focus", "name", 0);
            ui_model_set("players.previousCount", "1", 2);
            ui_model_set("players.nextCount", "0", 2);
            ui_model_set("players.name", "D", 0);
            ui_model_set("players.suffix", "aniel", 0);
            ui_model_set("players.tint", "#008fbe", 0);
            ui_model_set("players.light", "#91d7f0", 0);
            ui_model_set("players.color", "Blue", 0);
            ui_model_set("players.level", "Medium", 0);
            ui_model_set("players.voices", "1", 2);
            ui_model_set("players.voice", "Voice 4: Chorus", 0);
            const auto avatar_image = utf8(root / "themes/Modern/[name]noavatar.png");
            ui_model_array("players.profiles", 24);
            for (int i = 0; i < 24; ++i) {
                const auto prefix = "players.profiles[" + std::to_string(i) + "].";
                ui_model_set((prefix + "id").c_str(), std::to_string(i).c_str(), 1);
                ui_model_set((prefix + "name").c_str(), ("Player" + std::to_string(i + 1)).c_str(), 0);
                ui_model_set((prefix + "avatar").c_str(), avatar_image.c_str(), 0);
                ui_model_set((prefix + "tint").c_str(), "#008fbe", 0);
                ui_model_set((prefix + "avatarTint").c_str(), "#008fbe", 0);
                ui_model_set((prefix + "selected").c_str(), i == 0 ? "1" : "0", 2);
            }
            ui_model_set("players.avatarSelected", "2", 1);
            ui_model_set("players.avatarCount", "5", 1);
            ui_model_array("players.avatars", 5);
            for (int i = 0; i < 5; ++i) {
                const auto prefix = "players.avatars[" + std::to_string(i) + "].";
                ui_model_set((prefix + "slot").c_str(), std::to_string(i).c_str(), 1);
                ui_model_set((prefix + "id").c_str(), std::to_string(i).c_str(), 1);
                ui_model_set((prefix + "image").c_str(), avatar_image.c_str(), 0);
                ui_model_set((prefix + "tint").c_str(), "#008fbe", 0);
            }
            const auto mask_fixture = std::filesystem::current_path() / ("document-mask-test-" + std::to_string(SDL_GetPerformanceCounter()) + ".rml");
            {
                std::ofstream fixture(mask_fixture);
                fixture << R"(<rml><head><style>
                    body { margin: 0; width: 100%; height: 100%; }
                    div { display: block; position: absolute; top: 100px; width: 100px; height: 100px; }
                    #gradient { left: 100px; decorator: vertical-gradient(#ff0000b3 #f000); }
                    #masked { left: 300px; overflow: hidden; background-color: red; mask-image: vertical-gradient(#000000b3 #0000); }
                    #masked span { display: block; position: absolute; width: 100px; height: 200px; transform: scaleY(-1); }
                    </style></head><body><div id="gradient"/><div id="masked"><span/></div></body></rml>)";
            }
            require(ui_open(utf8(mask_fixture).c_str()) != 0, "Mask fixture");
            glClear(GL_COLOR_BUFFER_BIT); ui_render(1280, 720, 0);
            glReadPixels(150, 720-150, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            const int gradient_alpha = pixel[3];
            require(gradient_alpha > 60 && gradient_alpha < 120, "Gradient fixture must render a fading alpha");
            glReadPixels(350, 720-150, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);

            std::filesystem::remove(mask_fixture);
            require(std::abs(int(pixel[3]) - gradient_alpha) < 3, "A flipped child must not move its parent mask outside the clipping region");
            const auto players_document = utf8(root / "frontends/modern/players.rml");
            require(ui_open(players_document.c_str()) != 0, "Player setup document");
            ui_render(1280, 720, 0);
            float player_x, player_y, player_w, player_h;
            require(ui_bounds("profile-frame-23", &player_x, &player_y, &player_w, &player_h) != 0,
                "Player setup must display all 24 profiles");
            require(player_y > 270 && player_y < 320, "Compact player grid second row must remain above the avatar editor");
            // Bounds and pointer hit testing both include CSS transforms.
            ui_mouse(1190, 305, 0, 1); ui_mouse(1190, 305, 0, 0);
            require(std::string(ui_action()) == "players.select" && std::string(ui_action_target()) == "23",
                "The last compact profile must be reachable inside the viewport");
            ui_clear_action();
            require(ui_bounds("avatar-reflection-clip-1", &player_x, &player_y, &player_w, &player_h) != 0 && player_h > 50,
                "Avatar reflection clipping region must have a nonzero height");
            glClear(GL_COLOR_BUFFER_BIT); ui_render(1280, 720, 1);
            glReadPixels(400, 720-505, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[3] > 100 && pixel[3] < 210, "Avatar reflection must retain the native fading alpha");
            ui_focus("players-name");
            require(std::string(ui_focused_target()) == "name", "Name field focus target");
            ui_mouse(850, 420, 0, 1); ui_mouse(850, 420, 0, 0);
            require(std::string(ui_action()) == "players.avatar.select", "Neighbor avatar mouse selection");
            require(std::string(ui_focused_target()) == "avatar", "Avatar action argument must not replace its focus group");
            ui_clear_action();
            ui_mouse(640, 550, -1, 0);
            ui_focus("players-avatar");
            ui_mouse(640, 550, -1, 0);
            require(std::string(ui_focused_target()) == "avatar", "A stationary pointer must not steal keyboard focus");
            // Absolute native paths must not lose the POSIX root. Keep the
            // image outside cwd and assert its actual pixels, not just bounds:
            // a failed texture can still paint an opaque white rectangle.
            const auto absolute_fixture_root = std::filesystem::current_path() /
                ("document-absolute-assets-" + std::to_string(SDL_GetPerformanceCounter()));
            std::filesystem::create_directories(absolute_fixture_root);
            const auto absolute_fixture_image = absolute_fixture_root / "green.svg";
            const auto absolute_fixture_document = absolute_fixture_root / "screen.rml";
            {
                std::ofstream image(absolute_fixture_image);
                image << R"(<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><path fill="#00ff00" d="M0 0h32v32H0z"/></svg>)";
                std::ofstream fixture(absolute_fixture_document);
                fixture << R"(<rml><head><style>img{position:absolute;top:10px;width:32px;height:32px;}</style></head>
<body><div data-model="game"><img data-attr-src="data.absoluteAssets.source" style="left:10px;" />
<img src="green.svg" style="left:70px;" /></div></body></rml>)";
            }
            const auto absolute_fixture_source = utf8(absolute_fixture_image);
#ifndef _WIN32
            require(!absolute_fixture_source.empty() && absolute_fixture_source[0] == '/',
                "POSIX fixture must exercise a leading-slash absolute image path");
#endif
            const int absolute_fixture_warnings = warnings;
            ui_model_set("absoluteAssets.source", absolute_fixture_source.c_str(), 0);
            require(ui_open(utf8(absolute_fixture_document).c_str()) != 0, "Absolute image fixture");
            glClear(GL_COLOR_BUFFER_BIT); ui_render(1280,720,0);
            glReadPixels(20,720-20,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);
            require(pixel[0]<10 && pixel[1]>240 && pixel[2]<10 && pixel[3]>240,
                "Absolute model image must preserve its native filesystem root");
            glReadPixels(80,720-20,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);
            require(pixel[0]<10 && pixel[1]>240 && pixel[2]<10 && pixel[3]>240,
                "Sibling image must still resolve relative to the document");
            require(warnings == absolute_fixture_warnings, "Absolute image emitted loading diagnostics");
            require(ui_open(players_document.c_str()) != 0, "Release absolute image fixture");
            std::filesystem::remove(absolute_fixture_image); std::filesystem::remove(absolute_fixture_document);
            std::filesystem::remove(absolute_fixture_root);
            // Offstage entries have deliberately absent files. Only the visible window may request pixels.
            ui_model_set("players.avatarCount", "101", 1);
            ui_model_set("players.avatarSelected", "50", 1);
            ui_model_array("players.avatars", 101);
            for (int i = 0; i < 101; ++i) {
                const auto prefix = "players.avatars[" + std::to_string(i) + "].";
                ui_model_set((prefix + "id").c_str(), std::to_string(i).c_str(), 1);
                ui_model_set((prefix + "image").c_str(), i >= 47 && i <= 54 ? avatar_image.c_str() : "absent-offstage-avatar.png", 0);
                ui_model_set((prefix + "tint").c_str(), "#ffffff", 0);
            }
            require(ui_open(players_document.c_str()) != 0, "Large avatar list document");
            ui_render(1280, 720, 0);
            require(warnings == 0, "Offstage avatar images must stay unloaded");
            glReadPixels(50, 720-50, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[0] < 100 && pixel[2] > pixel[0] && pixel[3] > 240,
                "Preloading carousel neighbors must preserve the screen background");
            float before_x, before_y, before_w, before_h;
            require(ui_bounds("avatar-item-50", &before_x, &before_y, &before_w, &before_h) != 0, "Selected avatar exists");
            ui_model_set("players.avatarSelected", "51", 1);
            ui_render(1280, 720, 0);
            SDL_Delay(40); ui_render(1280, 720, 0);
            glReadPixels(50, 720-50, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            require(pixel[0] < 100 && pixel[2] > pixel[0] && pixel[3] > 240,
                "Animating carousel items must preserve the screen background");
            require(ui_bounds("avatar-item-50", &player_x, &player_y, &player_w, &player_h) != 0, "Moving avatar keeps its identity");
            require(player_x + player_w / 2 < before_x + before_w / 2 - 1 && player_x + player_w / 2 > 410, "Avatar must animate between positions instead of swapping images");
            for (int frame = 0; frame < 33; ++frame) { SDL_Delay(30); ui_render(1280, 720, 0); }
            require(ui_bounds("avatar-item-50", &player_x, &player_y, &player_w, &player_h) != 0 && std::abs(player_x + player_w / 2 - 404.4f) < 2,
                "Avatar must settle in its theme-defined neighboring slot");
            for (int i : {0, 1, 2, 3, 97, 98, 99, 100}) {
                const auto path = "players.avatars[" + std::to_string(i) + "].image";
                ui_model_set(path.c_str(), avatar_image.c_str(), 0);
            }
            ui_model_set("players.avatarSelected", "100", 1);
            for (int frame = 0; frame < 33; ++frame) { SDL_Delay(30); ui_render(1280, 720, 0); }
            ui_model_set("players.avatarSelected", "0", 1);
            for (int frame = 0; frame < 33; ++frame) { SDL_Delay(30); ui_render(1280, 720, 0); }
            require(ui_bounds("avatar-item-100", &player_x, &player_y, &player_w, &player_h) != 0 && std::abs(player_x + player_w / 2 - 404.4f) < 2,
                "Last avatar must wrap to the neighboring slot when the first is selected");
            require(ui_bounds("avatar-item-0", &player_x, &player_y, &player_w, &player_h) != 0 && std::abs(player_x + player_w / 2 - 644.8f) < 2,
                "Wrapped selection must settle on the first avatar");
            ui_model_set("players.avatarCount", "1", 1);
            ui_model_array("players.avatars", 1);
            ui_render(1280, 720, 0);
            require(ui_bounds("avatar-item-0", &player_x, &player_y, &player_w, &player_h) != 0 && std::abs(player_x + player_w / 2 - 644.8f) < 2,
                "A single-avatar list must remain centered without duplicate items");
            ui_model_set("players.count", "0", 1);
            ui_model_set("players.active", "0", 2);
            ui_model_array("players.profiles", 0);
            ui_render(1280, 720, 0);
            require(ui_bounds("players-name", &player_x, &player_y, &player_w, &player_h) == 0,
                "Lyrics-only setup must hide profile editing");
            const auto language_fixture = std::filesystem::current_path() / "document-language-test.rml";
            {
                std::ofstream fixture(language_fixture);
                fixture << R"(<rml><head><style>body{font-family:ui;font-size:20px;} span{display:inline-block;}</style></head>
<body><div data-model="game"><div data-for="row : data.languageTest.rows"><span lang="REPEATED_TEST" data-attr-id="'language-row-' + row.id"></span></div></div></body></rml>)";
            }
            ui_model_array("languageTest.rows", 0);
            require(ui_open(utf8(language_fixture).c_str()) != 0, "Repeated translation fixture");
            ui_render(1280, 720, 0);
            ui_model_array("languageTest.rows", 1);
            ui_model_set("languageTest.rows[0].id", "0", 1);
            ui_render(1280, 720, 0);
            require(ui_bounds("language-row-0", &player_x, &player_y, &player_w, &player_h) != 0 && player_w > 190,
                "Labels created after opening must receive their translation");
            ui_model_array("languageTest.rows", 0);
            ui_render(1280, 720, 0);
            ui_model_array("languageTest.rows", 1);
            ui_model_set("languageTest.rows[0].id", "1", 1);
            ui_render(1280, 720, 0);
            require(ui_bounds("language-row-1", &player_x, &player_y, &player_w, &player_h) != 0 && player_w > 190,
                "Recreated repeated labels must receive their translation");
            // Open through the platform-native path, from outside the asset directory.
            // A missing relative texture can still produce a white rectangle, so assert
            // its rendered color, both before and after a repeated row is recreated.
            const auto relative_root = std::filesystem::current_path() /
                ("document-relative-assets-" + std::to_string(SDL_GetPerformanceCounter()));
            std::filesystem::create_directories(relative_root / "images");
            const auto relative_document = relative_root / "screen.rml";
            {
                std::ofstream red(relative_root / "images/red.svg");
                red << R"(<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><path fill="#ff0000" d="M0 0h32v32H0z"/></svg>)";
                std::ofstream green(relative_root / "images/green.svg");
                green << R"(<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><path fill="#00ff00" d="M0 0h32v32H0z"/></svg>)";
                std::ofstream blue(relative_root / "images/blue.svg");
                blue << R"(<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><path fill="#0000ff" d="M0 0h32v32H0z"/></svg>)";
                std::ofstream fixture(relative_document);
                fixture << R"(<rml><head><style>img{position:absolute;width:32px;height:32px;} .row{position:absolute;left:70px;top:10px;}</style></head>
<body><div data-model="game"><img src="images/red.svg" style="left:10px;top:10px;" />
<div data-for="row : data.relativeAssets.rows" class="row"><img src="images/green.svg" /></div>
<img data-attr-src="data.relativeAssets.absoluteSource" style="left:130px;top:10px;" /></div></body></rml>)";
            }
            auto native_document = utf8(relative_document);
#ifdef _WIN32
            for (auto& c : native_document) if (c == '/') c = '\\';
#endif
            ui_model_array("relativeAssets.rows", 0);
            ui_model_set("relativeAssets.absoluteSource", utf8(relative_root / "images/blue.svg").c_str(), 0);
            const int relative_warnings = warnings;
            require(ui_open(native_document.c_str()) != 0, "Native-separator image document");
            for (int recreation = 0; recreation < 2; ++recreation) {
                ui_model_array("relativeAssets.rows", 1);
                glClear(GL_COLOR_BUFFER_BIT); ui_render(1280,720,0);
                glReadPixels(20,720-20,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);
                require(pixel[0]>240 && pixel[1]<10 && pixel[2]<10 && pixel[3]>240,
                    "Static image must resolve relative to the native-path document");
                glReadPixels(80,720-20,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);
                require(pixel[0]<10 && pixel[1]>240 && pixel[2]<10 && pixel[3]>240,
                    "Repeated image must retain the owning document's asset directory");
                glReadPixels(140,720-20,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);
                require(pixel[0]<10 && pixel[1]<10 && pixel[2]>240 && pixel[3]>240,
                    "An absolute model image path must keep working");
                ui_model_array("relativeAssets.rows", 0); ui_render(1280,720,0);
            }
            require(warnings == relative_warnings, "Native-path relative images emitted loading diagnostics");
            require(ui_open(main_document.c_str()) != 0, "Release relative image fixture");
            for (const char* name : {"red.svg", "green.svg", "blue.svg"})
                std::filesystem::remove(relative_root / "images" / name);
            std::filesystem::remove(relative_document);
            std::filesystem::remove(relative_root / "images"); std::filesystem::remove(relative_root);
            {
                std::ofstream fixture(language_fixture);
                fixture << R"(<rml><head><style>div{display:block;} .probe{position:absolute;height:10px;}</style></head>
<body><div data-model="game">
<div id="math-sin" class="probe" data-style-width="((data.math.angle | sin) + 1) * 100 + 'px'" />
<div id="math-cos" class="probe" data-style-width="((data.math.angle | cos) + 1) * 100 + 'px'" />
<div id="math-clamp" class="probe" data-style-width="((data.math.value | abs) | min(80) | max(20)) + 'px'" />
</div></body></rml>)";
            }
            ui_model_set("math.angle", "1.5707963267948966", 3);
            ui_model_set("math.value", "-120", 3);
            require(ui_open(utf8(language_fixture).c_str()) != 0, "Theme math fixture");
            ui_render(1280, 720, 0);
            require(ui_bounds("math-sin", &player_x, &player_y, &player_w, &player_h) != 0 && std::abs(player_w - 200) < 1,
                "Theme sine transform uses radians");
            require(ui_bounds("math-cos", &player_x, &player_y, &player_w, &player_h) != 0 && std::abs(player_w - 100) < 1,
                "Theme cosine transform uses radians");
            require(ui_bounds("math-clamp", &player_x, &player_y, &player_w, &player_h) != 0 && std::abs(player_w - 80) < 1,
                "Theme absolute/min/max transforms compose");
            ui_model_set("math.value", "-5", 3);
            ui_render(1280, 720, 0);
            require(ui_bounds("math-clamp", &player_x, &player_y, &player_w, &player_h) != 0 && std::abs(player_w - 20) < 1,
                "Theme math responds to model updates");
            {
                std::ofstream fixture(language_fixture);
                fixture << R"(<rml><head><style>body{font-family:ui;} .fit{display:block;width:80px;height:30px;font-size:20px;white-space:nowrap;} span{display:inline-block;}</style></head>
<body><div data-model="game"><div class="fit" fit-text="1"><span id="fitted-glyphs">{{ data.fit.caption }}</span></div></div></body></rml>)";
            }
            ui_model_set("fit.caption", "A", 0);
            require(ui_open(utf8(language_fixture).c_str()) != 0, "Model text-fit fixture"); ui_render(1280,720,0);
            ui_model_set("fit.caption", std::string(60,'B').c_str(), 0); ui_prepare(1280,720);
            require(ui_bounds("fitted-glyphs", &player_x,&player_y,&player_w,&player_h) != 0 && player_w <= 81,
                "Longer model text must refit to its container width");
            ui_model_set("fit.caption", "A", 0); ui_prepare(1280,720);
            require(ui_bounds("fitted-glyphs", &player_x,&player_y,&player_w,&player_h) != 0 && player_h > 18,
                "Shorter model text must restore the theme font size");
            {
                std::ofstream fixture(language_fixture);
                fixture << R"(<rml><head><style>.parent{position:absolute;left:100px;top:70px;width:200px;height:100px;transform-origin:0% 0%;transform:translate(30px,20px) scale(1.5);} button{position:absolute;left:10px;top:20px;width:80px;height:40px;border-width:0;padding:0;}</style></head>
<body><div class="parent"><button id="transformed-region" action="transformed" target="hit" /></div></body></rml>)";
            }
            require(ui_open(utf8(language_fixture).c_str()) != 0, "Transformed Region fixture");
            ui_prepare(1280,720);
            require(ui_bounds("transformed-region", &player_x,&player_y,&player_w,&player_h) != 0 &&
                std::abs(player_x-145)<1 && std::abs(player_y-120)<1 && std::abs(player_w-120)<1 && std::abs(player_h-60)<1,
                "Native Region bounds must include ancestor translation and scale");
            ui_mouse(205,150,0,1); ui_mouse(205,150,0,0);
            require(std::string(ui_action()) == "transformed", "Transformed Region center must match pointer input"); ui_clear_action();
            {
                std::ofstream fixture(language_fixture);
                fixture << R"(<rml><head><style>body{font-family:ui;} button{display:block;width:100px;height:25px;} .rows{display:block;width:500px;height:80px;overflow-y:auto;} .row{display:block;width:500px;height:25px;}</style></head>
<body><button id="retained-a" action="choose" target="a">A</button><button id="retained-b" action="choose" target="b">B</button>
<div data-model="game"><div id="retained-scroll" class="rows"><div class="row" data-for="row : data.retained.rows" data-attr-id="'retained-row-' + row.id">{{ row.id }}</div></div></div></body></rml>)";
            }
            const auto base_handle = ui_create(utf8(language_fixture).c_str(), "retained.rows");
            require(base_handle != 0, "Retained base creation");
            ui_model_array("retained.rows", 30);
            for (int i=0; i<30; ++i) ui_model_set(("retained.rows[" + std::to_string(i) + "].id").c_str(), std::to_string(i).c_str(), 1);
            ui_render(1280,720,0); ui_focus("retained-b");
            ui_scroll_to("retained-scroll", 0.5f);
            require(std::abs(ui_scroll_position("retained-scroll") - 0.5f) < 0.01f, "Named scrolling uses actual DOM overflow");
            ui_scroll_to("retained-scroll", 2.f);
            require(ui_scroll_position("retained-scroll") > 0.99f, "Named scrolling clamps to the content end");
            ui_reveal("retained-row-20");
            float retained_x, retained_y, retained_w, retained_h;
            require(ui_bounds("retained-row-20", &retained_x,&retained_y,&retained_w,&retained_h) != 0, "Retained base row");
            const auto popup_handle = ui_create(utf8(language_fixture).c_str(), "retained.rows");
            require(popup_handle != 0 && popup_handle != base_handle, "Independent popup creation");
            ui_model_array("retained.rows", 1); ui_model_set("retained.rows[0].id", "90", 1);
            ui_render(1280,720,0); ui_focus("retained-a");
            ui_scroll_to("retained-scroll", 0.5f);
            require(ui_scroll_position("retained-scroll") == 0 && ui_scroll_position("missing-scroll") == 0,
                "Short or missing content has no normalized scroll extent");
            require(ui_select(base_handle) != 0 && std::string(ui_focused_target()) == "b", "Popup must preserve base focus");
            require(ui_bounds("retained-row-20", &player_x,&player_y,&player_w,&player_h) != 0 && std::abs(player_y-retained_y)<0.5f,
                "Popup must preserve base scroll and array content");
            require(ui_bounds("retained-row-90", &player_x,&player_y,&player_w,&player_h) == 0, "Popup model must not alter base rows");
            ui_render(1024,768,0);
            require(ui_select(popup_handle) != 0, "Retained popup selection"); ui_render(1024,768,0);
            require(ui_bounds("retained-row-90", &player_x,&player_y,&player_w,&player_h) != 0, "Popup retains its own model after resize");
            ui_destroy(popup_handle);
            require(ui_select(popup_handle) == 0 && ui_select(base_handle) != 0, "Destroyed handles must be rejected");
            require(std::string(ui_focused_target()) == "b", "Destroying popup preserves base focus");
            const auto replacement_handle = ui_create(utf8(language_fixture).c_str(), "retained.rows");
            require(replacement_handle > popup_handle && ui_select(popup_handle) == 0, "Handles must not be reused");
            ui_destroy(replacement_handle); ui_destroy(base_handle); require(ui_select(0) != 0, "Default context remains available");
            std::filesystem::remove(language_fixture);
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
