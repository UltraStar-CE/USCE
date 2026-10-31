// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <RmlUi/Core.h>

namespace DocumentModel {
bool Initialize(Rml::Context* context);
void Reset();
void Set(const Rml::String& path, const Rml::String& value, int type = 0);
void Array(const Rml::String& path, int count);
}
