// SPDX-License-Identifier: GPL-2.0-or-later
#include "document-model.h"
#include <map>
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
    model = constructor.GetModelHandle();
    return true;
}
void Reset() { model = {}; root = {}; }
void Set(const Rml::String& path, const Rml::String& text, int type) {
    auto* node = Resolve(path);
    if (!node) return;
    Rml::Variant value(text);
    if (type == 1) value = value.Get<int>();
    else if (type == 2) value = text == "1" || text == "true";
    else if (type == 3) value = value.Get<double>();
    if (node->kind == Node::Value && node->value == value) return;
    node->kind = Node::Value; node->value = std::move(value);
    if (model) model.DirtyVariable("data");
}
void Array(const Rml::String& path, int count) {
    auto* node = Resolve(path);
    if (!node || count < 0 || count > 100000) return;
    if (node->kind == Node::Array && node->items.size() == size_t(count)) return;
    node->kind = Node::Array;
    node->items.resize(count);
    if (model) model.DirtyVariable("data");
}
}
