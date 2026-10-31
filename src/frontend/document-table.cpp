// SPDX-License-Identifier: GPL-2.0-or-later
#include "document-table.h"
#include <RmlUi/Core.h>
#include <RmlUi/Core/ElementText.h>
#include <RmlUi/Core/ElementUtilities.h>
#include <algorithm>
#include <cmath>
#include <functional>
#include <unordered_map>
#include <vector>

namespace DocumentTables {
namespace {
using Elements = std::vector<Rml::Element*>;
struct CacheEntry { Rml::ObserverPtr<Rml::Element> element; size_t signature; };
std::unordered_map<Rml::Element*, CacheEntry> signatures;

void Hash(size_t& result, const Rml::String& value) {
    result ^= std::hash<Rml::String>{}(value) + size_t(0x9e3779b9) + (result << 6) + (result >> 2);
}
void Pixels(Rml::Element* element, const char* property, float value) {
    element->SetProperty(property, Rml::ToString(value) + "px");
}
Rml::String Text(Rml::Element* element) {
    if (auto* text = rmlui_dynamic_cast<Rml::ElementText*>(element))
        return Rml::StringUtilities::DecodeRml(text->GetText());
    Rml::String result;
    for (int i = 0; i < element->GetNumChildren(); ++i) result += Text(element->GetChild(i));
    return result;
}
Elements Children(Rml::Element* parent) {
    Elements result;
    if (parent) for (int i = 0; i < parent->GetNumChildren(); ++i) {
        auto* child = parent->GetChild(i);
        if (!child->HasAttribute("data-for")) result.push_back(child);
    }
    return result;
}
Elements Find(Rml::Element* parent, const char* selector) {
    Elements result, all;
    parent->QuerySelectorAll(all, selector);
    for (auto* element : all) if (!element->HasAttribute("data-for")) result.push_back(element);
    return result;
}
Rml::Element* First(Rml::Element* parent, const char* selector) {
    auto all = Find(parent, selector);
    return all.empty() ? nullptr : all.front();
}
float Number(Rml::Element* element, const char* name, float fallback) {
    return element->GetAttribute<float>(name, fallback);
}

struct Column {
    float minimum = 0, gap = 0, natural = 0, width = 0, left = 0;
    bool flexible = false;
};
struct Metrics { float font = 0, pitch = 0; };
Metrics RowMetrics(Rml::Element* root, int rows, float height, float maximum, float minimum) {
    const float min_rows = std::max(1.f, Number(root, "min-layout-rows", 5));
    const float layout_rows = std::max(min_rows, float(rows)) + std::max(0.f, Number(root, "padding-rows", 2));
    const float density_min = Number(root, "density-min", 5);
    const float density_max = std::max(density_min + 1, Number(root, "density-max", 30));
    const float requested = Number(root, "density-count", float(rows));
    float density = std::clamp((requested - density_min) / (density_max - density_min), 0.f, 1.f);
    density = std::pow(density, std::max(0.01f, Number(root, "density-curve", 2)));
    const float ratio = std::max(0.01f, Number(root, "font-relaxed", .78f) + density *
        (Number(root, "font-dense", 1.10f) - Number(root, "font-relaxed", .78f)));
    const float line_height = std::max(0.01f, Number(root, "line-height-factor", .85f));
    Metrics result;
    result.font = std::clamp(height / ((layout_rows - 1) / ratio + line_height), minimum, maximum);
    result.pitch = std::max(0.f, (height - result.font * line_height) / std::max(1.f, layout_rows - 1));
    result.pitch = std::min(result.pitch, result.font / .78f + maximum / 12.f);
    return result;
}
std::vector<Column> Measure(Rml::Element* root, Rml::Element* header, const Elements& rows,
    float panel_width, float font) {
    const auto headers = Children(header);
    size_t count = headers.size();
    for (auto* row : rows) count = std::max(count, Children(row).size());
    std::vector<Column> columns(count);
    const float padding = std::max(0.f, Number(root, "column-padding", .25f)) * font;
    for (size_t i = 0; i < count; ++i) {
        if (i < headers.size()) {
            columns[i].minimum = std::max(std::max(0.f, Number(headers[i], "column-min", 0)) * panel_width,
                std::max(0.f, Number(headers[i], "column-min-em", 0)) * font);
            columns[i].gap = std::max(0.f, Number(headers[i], "column-gap", 0)) * panel_width;
            columns[i].flexible = headers[i]->GetAttribute<int>("column-flex", 0) != 0;
            columns[i].natural = float(Rml::ElementUtilities::GetStringWidth(headers[i], Text(headers[i]))) + padding;
        }
        for (auto* row : rows) {
            const auto cells = Children(row);
            if (i < cells.size()) columns[i].natural = std::max(columns[i].natural,
                float(Rml::ElementUtilities::GetStringWidth(cells[i], Text(cells[i]))) + padding);
        }
        if (i < headers.size()) {
            const float cap = Number(headers[i], "column-measure-max", 0);
            if (cap > 0) columns[i].natural = std::min(columns[i].natural, cap * panel_width);
        }
    }
    return columns;
}
float NaturalWidth(const std::vector<Column>& columns) {
    float result = 0;
    for (const auto& column : columns) result += column.gap + std::max(column.minimum, column.natural);
    return result;
}
void Allocate(std::vector<Column>& columns, float width) {
    float used = 0;
    int flexible = 0;
    for (auto& column : columns) {
        column.width = column.flexible ? column.minimum : std::max(column.minimum, column.natural);
        used += column.gap + column.width;
        flexible += int(column.flexible);
    }
    const float extra = std::max(0.f, width - used) / std::max(1, flexible);
    const float scale = used > width && used > 0 ? width / used : 1.f;
    float x = 0;
    for (auto& column : columns) {
        x += column.gap * scale;
        column.left = x;
        column.width = (column.width + (column.flexible ? extra : 0)) * scale;
        x += column.width;
    }
}
void PositionCells(Rml::Element* row, const std::vector<Column>& columns) {
    const auto cells = Children(row);
    for (size_t i = 0; i < cells.size(); ++i) {
        auto* cell = cells[i];
        cell->SetProperty("display", i < columns.size() ? "block" : "none");
        if (i >= columns.size()) continue;
        cell->SetProperty("position", "absolute");
        Pixels(cell, "left", columns[i].left); Pixels(cell, "width", columns[i].width);
        Pixels(cell, "top", 0);
    }
}
void Arrange(Rml::Element* root, Rml::Context* context) {
    auto panels = Find(root, ".table-panel");
    if (panels.empty()) return;
    const auto rows = Find(panels.front(), ".data-row");
    auto* header = First(panels.front(), ".table-header");
    const auto dimensions = context->GetDimensions();
    const float width = root->GetBox().GetSize(Rml::BoxArea::Content).x;
    const float height = root->GetBox().GetSize(Rml::BoxArea::Content).y;
    if (width <= 0 || height <= 0) return;
    size_t signature = 0;
    Hash(signature, Rml::ToString(dimensions.x) + ":" + Rml::ToString(dimensions.y));
    Hash(signature, Rml::ToString(width) + ":" + Rml::ToString(height));
    for (const char* name : {"max-columns", "split-min-rows", "split-min-gain", "table-gap", "min-font-ratio", "min-layout-rows",
        "padding-rows", "first-row-offset", "density-count", "density-min", "density-max", "density-curve",
        "font-relaxed", "font-dense", "line-height-factor", "column-padding"})
        Hash(signature, root->GetAttribute<Rml::String>(name, ""));
    for (auto* cell : Children(header)) {
        Hash(signature, Text(cell)); Hash(signature, cell->GetClassNames());
        for (const char* name : {"column-min", "column-min-em", "column-gap", "column-flex", "column-measure-max"})
            Hash(signature, cell->GetAttribute<Rml::String>(name, ""));
    }
    for (auto* row : rows) {
        Hash(signature, row->GetClassNames());
        for (auto* cell : Children(row)) { Hash(signature, Text(cell)); Hash(signature, cell->GetClassNames()); }
    }
    const auto cached = signatures.find(root);
    if (cached != signatures.end() && cached->second.element.get() == root && cached->second.signature == signature) return;

    root->RemoveProperty(Rml::PropertyId::FontSize);
    for (auto* panel : panels) panel->SetProperty("display", "block");
    context->Update();
    const float maximum = std::max(1.f, root->GetComputedValues().font_size());
    const float minimum = std::clamp(Number(root, "min-font-ratio", .4f), .01f, 1.f) * maximum;
    const float gap = std::max(0.f, Number(root, "table-gap", 2.666667f)) * maximum;
    int chosen_panels = 1;
    auto chosen = RowMetrics(root, int(rows.size()), height, maximum, minimum);
    const int max_panels = std::clamp(root->GetAttribute<int>("max-columns", 2), 1, int(panels.size()));
    if (int(rows.size()) >= root->GetAttribute<int>("split-min-rows", 20)) {
        for (int count = 2; count <= max_panels; ++count) {
            const float panel_width = (width - gap * (count - 1)) / count;
            if (panel_width <= 0) break;
            auto trial = RowMetrics(root, int((rows.size() + count - 1) / count), height, maximum, minimum);
            const float lower_font = std::max(minimum, chosen.font * Number(root, "split-min-gain", 1.1f));
            while (trial.font >= lower_font) {
                Pixels(root, "font-size", trial.font); context->Update();
                if (NaturalWidth(Measure(root, header, rows, panel_width, trial.font)) <= panel_width + .5f) {
                    chosen_panels = count; chosen = trial;
                    const float layout_rows = std::max(Number(root, "min-layout-rows", 5),
                        float((rows.size() + count - 1) / count)) + Number(root, "padding-rows", 2);
                    chosen.pitch = std::max(0.f, (height - chosen.font * Number(root, "line-height-factor", .85f)) /
                        std::max(1.f, layout_rows - 1));
                    chosen.pitch = std::min(chosen.pitch, chosen.font / .78f + maximum / 12.f);
                    break;
                }
                if (trial.font <= lower_font) break;
                trial.font = std::max(lower_font, trial.font * .95f);
            }
        }
    }
    Pixels(root, "font-size", chosen.font); context->Update();
    const float panel_width = (width - gap * (chosen_panels - 1)) / chosen_panels;
    auto columns = Measure(root, header, rows, panel_width, chosen.font);
    Allocate(columns, panel_width);
    const int rows_per_panel = std::max(1, int((rows.size() + chosen_panels - 1) / chosen_panels));
    root->SetClass("split", chosen_panels > 1);
    root->SetAttribute("table-columns", chosen_panels);
    for (size_t panel_index = 0; panel_index < panels.size(); ++panel_index) {
        auto* panel = panels[panel_index];
        panel->SetProperty("display", int(panel_index) < chosen_panels ? "block" : "none");
        panel->SetProperty("position", "absolute");
        Pixels(panel, "left", float(panel_index) * (panel_width + gap)); Pixels(panel, "width", panel_width);
        if (auto* heading = First(panel, ".table-header")) PositionCells(heading, columns);
        if (auto* body = First(panel, ".table-rows")) Pixels(body, "width", panel_width);
        auto panel_rows = Find(panel, ".data-row");
        for (size_t index = 0; index < panel_rows.size(); ++index) {
            auto* row = panel_rows[index];
            const int row_panel = int(index) / rows_per_panel;
            row->SetProperty("display", row_panel == int(panel_index) ? "block" : "none");
            row->SetProperty("position", "absolute");
            Pixels(row, "left", 0); Pixels(row, "width", panel_width);
            Pixels(row, "top", (float(index % rows_per_panel) + Number(root, "first-row-offset", 1)) * chosen.pitch);
            Pixels(row, "height", std::max(chosen.pitch, chosen.font));
            PositionCells(row, columns);
        }
    }
    context->Update();
    signatures[root] = {root->GetObserverPtr(), signature};
}
}
void ClearCache() { signatures.clear(); }
void Layout(Rml::ElementDocument* document, Rml::Context* context) {
    if (!document || !context) return;
    Elements tables;
    document->QuerySelectorAll(tables, "[adaptive-table]");
    for (auto* table : tables) Arrange(table, context);
}
}
