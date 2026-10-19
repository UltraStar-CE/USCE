# Recent name suggestions

Player, party player, party team and tournament name fields share a list of
the 256 most recently used names. Continuing forward from a name-entry screen
promotes its active names. Going back does not change recency. The history is
saved in the `RecentNames` section of the existing configuration file.

The first character typed after entering a field replaces its existing name.
Further typing appends. Backspace edits the current name and subsequent typing
continues that edit. Moving to another field resets this behavior; moving the
mouse within the same field does not.

A suggestion appears only after typing or editing a name. The most recently
used matching name is suggested, with case-insensitive prefix matching. Typed
letters remain opaque; the suggested suffix uses 50% opacity by default.

Changing focus accepts the suggestion. Enter accepts it without leaving the
screen; a subsequent Enter continues normally. Escape dismisses it and keeps
the typed prefix; a subsequent Escape performs the usual back action.
Selecting an existing field or loading a name template does not start a prediction.

Themes can override the opacity in their theme INI:

```ini
[NameSuggestions]
Alpha=0.5
```

The range is 0 to 1. Zero disables suggestions. Names and their suffixes use
the existing field's font, color and alignment.

Developer check: compile `tools/tests/recent_names_test.pas` with Free Pascal
and `-Fusrc/base`, putting executable and unit output in a temporary directory.
