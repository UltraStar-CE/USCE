// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
namespace Rml { class ElementDocument; class Context; }
namespace DocumentTables {
// Clear when documents/styles are replaced. No DOM pointers survive this call.
void ClearCache();
// Called after model/layout update and before drawing or querying bounds.
void Layout(Rml::ElementDocument* document, Rml::Context* context);
}
