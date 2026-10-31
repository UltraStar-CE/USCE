// SPDX-License-Identifier: GPL-2.0-or-later
#include "document-model.h"
#include <map>
#include <algorithm>
#include <cmath>
#include <vector>

namespace DocumentModel {
struct Node {
    enum Kind { Value, Object, Array } kind = Value;
    Rml::Variant value{Rml::String()};
    std::map<Rml::String, Node> members;
    std::vector<Node> items;
};
static Node root;
static Rml::DataModelHandle model;
static Rml::DataVariable Variable(Node& node);

class Definition final : public Rml::VariableDefinition {
public:
    explicit Definition(Rml::DataVariableType type) : VariableDefinition(type) {}
    bool Get(void* pointer, Rml::Variant& value) override {
        value = static_cast<Node*>(pointer)->value;
        return true;
    }
    // Observed game state is read-only. Changes go through named game actions.
    bool Set(void*, const Rml::Variant&) override { return false; }
    int Size(void* pointer) override { return int(static_cast<Node*>(pointer)->items.size()); }
    Rml::DataVariable Child(void* pointer, const Rml::DataAddressEntry& address) override {
        auto& node = *static_cast<Node*>(pointer);
        if (node.kind == Node::Array) {
            if (address.name == "size") return Rml::MakeLiteralIntVariable(int(node.items.size()));
            if (address.index < 0 || size_t(address.index) >= node.items.size()) return {};
            return Variable(node.items[address.index]);
        }
        return Variable(node.members[address.name]);
    }
};
static Definition scalar(Rml::DataVariableType::Scalar);
static Definition object(Rml::DataVariableType::Struct);
static Definition array(Rml::DataVariableType::Array);
static Rml::DataVariable Variable(Node& node) {
    return {node.kind == Node::Array ? &array : node.kind == Node::Object ? &object : &scalar, &node};
}

// Resolve named paths such as players[2].name without screen-specific C++ structs.
static Node* Resolve(const Rml::String& path) {
    if (path.empty()) return nullptr;
    auto* node = &root;
    size_t position = 0;
    while (position < path.size()) {
        if (path[position] == '.') { ++position; continue; }
        if (path[position] == '[') {
            const auto end = path.find(']', position);
            if (end == Rml::String::npos) return nullptr;
            const auto text = path.substr(position+1, end-position-1);
            int index = -1;
            if (!Rml::TypeConverter<Rml::String, int>::Convert(text, index) || index < 0 || index > 100000) return nullptr;
            node->kind = Node::Array;
            if (node->items.size() <= size_t(index)) node->items.resize(size_t(index)+1);
            node = &node->items[index]; position = end+1;
        } else {
            const auto end = path.find_first_of(".[", position);
            const auto name = path.substr(position, end == Rml::String::npos ? end : end-position);
            if (name.empty()) return nullptr;
            node->kind = Node::Object;
            node = &node->members[name];
            position = end == Rml::String::npos ? path.size() : end;
        }
    }
    return node;
}

bool Initialize(Rml::Context* context) {
    root = {}; root.kind = Node::Object;
    auto constructor = context->CreateDataModel("game");
    if (!constructor) return false;
    if (!constructor.RegisterCustomDataVariableDefinition<Node>(Rml::MakeUnique<Definition>(Rml::DataVariableType::Struct))) return false;
    if (!constructor.Bind("data", &root)) return false;
    constructor.RegisterTransformFunc("cyclic_offset", [](const Rml::VariantList& arguments) -> Rml::Variant {
        if (arguments.size() != 2) return Rml::Variant(0);
        const int count = arguments[1].Get<int>();
        if (count <= 0) return Rml::Variant(0);
        int offset = arguments[0].Get<int>() % count;
        if (offset * 2LL < -count) offset += count;
        if (offset * 2LL > count) offset -= count;
        return Rml::Variant(offset);
    });
    // Theme expressions use radians; the game supplies raw positions only.
    constructor.RegisterTransformFunc("sin", [](const Rml::VariantList& arguments) -> Rml::Variant {
        return arguments.size() == 1 ? Rml::Variant(std::sin(arguments[0].Get<double>())) : Rml::Variant(0);
    });
    constructor.RegisterTransformFunc("cos", [](const Rml::VariantList& arguments) -> Rml::Variant {
        return arguments.size() == 1 ? Rml::Variant(std::cos(arguments[0].Get<double>())) : Rml::Variant(0);
    });
    constructor.RegisterTransformFunc("abs", [](const Rml::VariantList& arguments) -> Rml::Variant {
        return arguments.size() == 1 ? Rml::Variant(std::abs(arguments[0].Get<double>())) : Rml::Variant(0);
    });
    constructor.RegisterTransformFunc("min", [](const Rml::VariantList& arguments) -> Rml::Variant {
        return arguments.size() == 2 ? Rml::Variant(std::min(arguments[0].Get<double>(), arguments[1].Get<double>())) : Rml::Variant(0);
    });
    constructor.RegisterTransformFunc("max", [](const Rml::VariantList& arguments) -> Rml::Variant {
        return arguments.size() == 2 ? Rml::Variant(std::max(arguments[0].Get<double>(), arguments[1].Get<double>())) : Rml::Variant(0);
    });
    model = constructor.GetModelHandle();
    return true;
}
void Reset() { model = {}; root = {}; }
bool Set(const Rml::String& path, const Rml::String& text, int type) {
    auto* node = Resolve(path);
    if (!node) return false;
    Rml::Variant value(text);
    if (type == 1) value = value.Get<int>();
    else if (type == 2) value = text == "1" || text == "true";
    else if (type == 3) value = value.Get<double>();
    if (node->kind == Node::Value && node->value == value) return false;
    node->kind = Node::Value; node->value = std::move(value);
    if (model) model.DirtyVariable("data");
    return true;
}
bool Array(const Rml::String& path, int count) {
    auto* node = Resolve(path);
    if (!node || count < 0 || count > 100000) return false;
    if (node->kind == Node::Array && node->items.size() == size_t(count)) return false;
    node->kind = Node::Array;
    node->items.resize(count);
    if (model) model.DirtyVariable("data");
    return true;
}
}
