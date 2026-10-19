# AGE filtering

Song files can contain a suitability value selected by the library owner:

```text
#AGE:12, DE:16, US:13
```

This uses the proposed AGE grammar from the UltraStar format discussion:
one or more comma-separated entries, each containing a positive integer from
1 to 999, optionally prefixed with a country or rating authority and a colon.
Country and authority names contain at least two letters. A value without a
prefix is the default. Duplicate prefixes and malformed values are unrated.
Existing AGE text is preserved when saving songs in the editor.

Choose **Options → Game → Age rating country**. Country choices use ISO codes,
such as DE for Germany and AT for Austria. The first default comes from the
operating system's country/region setting, or the regional locale on Linux.
Timezone is not used. Your saved selection takes precedence thereafter.
**Default / local** always uses the unprefixed value.

Search by **Age** to use `12`, `<12`, `<=12`, `>12` or `>=12`.
The active country appears beside Age. A matching country entry takes
precedence over the default. Without either entry the song is unrated and
does not match a numeric age search. Search `?` to find unrated songs.
For an explicit country or authority in one search, use `DE:<=14` or
`PEGI:<=12`; this does not change your saved country setting.
Clearing the search removes the age filter.

These values describe the local library's suitability choices. USCE does not
assign ratings, determine a player's age or download age information.

Developer check: compile `tools/tests/age_test.pas` with Free Pascal and
`-Fusrc/base`, placing its executable and units in a temporary build directory.
