## USCE in your language

### Table of Contents

1. [Introduction](#1-introduction)
2. [Translate texts](#2-translate-texts)
3. [Wildcards](#3-wildcards)

---

### 1. Introduction:

USCE uses `English.ini` as the source template for game translations. To add a new
language, copy `English.ini` to `[Language].ini`, with `[Language]` replaced by the
English name of the target language (for example, `German.ini` for German).

Translate all texts according to section (2) of this file.

---

### 2. Translate texts:

1. For each target language there is a translation file named `[Language].ini` where `[Language]`
   is the target language.
2. Keep the same sections and keys as `English.ini`. Only translate the text after the `=`.
3. Set the `LANGUAGE` value to the native display name of the language.
4. Existing translation files may contain lines prefixed with `;TODO:` like the following line:

   ```
   ;TODO: SOME_OPTION=English text here
   ```

5. Translate the text if you are familiar with the target language. After you have done so,
   remove the `;TODO: ` prefix so that it looks like in this German translation:

   ```
   SOME_OPTION=Hier der deutsche Text
   ```

   IMPORTANT: Do NOT remove the `;TODO: ` prefix if you did not translate the text and it is still English.
6. At the end of the file there might be some lines which start with `;INVALID: ` or `;UNUSED: `.
   Invalid lines are not correctly formatted lines and might crash USCE. Unused lines are not used
   anymore by USCE or they have been renamed.
7. If you want you may add your name to the END (not the beginning) of the file:

   ```
   ;TRANSLATOR: Mario Translatori
   ```

   Note the `;` in front of it.
8. Share your translation by opening a pull request. See
   [Contributing to USCE](../../CONTRIBUTING.md) for the contribution process.

---

### 3. Wildcards:

Here are some informations about the wildcards in the language texts for the statistic screens (`STAT_...`):
Information that will replace the wildcards:


#### `STAT_OVERVIEW_LIBRARY_TOTAL`
Format:

- `%0:d` Count Songs
- `%1:d` Count Artists


#### `STAT_OVERVIEW_LIBRARY_VIDEO`
Format:

- `%0:d` Count of Songs with Video
- `%1:d` Count of Songs without Video


#### `STAT_OVERVIEW_RESET`
Format:

- `%0:d` Day of Reset
- `%1:d` Month of Reset
- `%2:d` Year of Reset


#### `STAT_OVERVIEW_SCORE_ACTIVITY`
Format:

- `%0:d` Count Scores
- `%1:d` Count Players
- `%2:d` Count Songs with Scores


#### `STAT_OVERVIEW_AVERAGE_SCORE`
Format:

- `%0:d` Average Score


#### `STAT_OVERVIEW_COVERAGE`
Format:

- `%0:s` Percent of library with scores, including the percent sign


#### `STAT_OVERVIEW_SCORE_DENSITY`
Format:

- `%0:s` Average scores per player
- `%1:s` Average scores per scored song


#### `STAT_OVERVIEW_RECENT_AVERAGE`
Format:

- `%0:d` Average score in the selected recent period
- `%1:s` Signed score difference versus the overall average


#### `STAT_OVERVIEW_RECENT_SHARE`
Format:

- `%0:s` Percent of all saved scores recorded in the selected recent period, including the percent sign


#### `STAT_OVERVIEW_FUN_SCORED_SONG`
Format:

- `%0:s` Average scores per scored song


#### `STAT_OVERVIEW_FUN_RECENT_PLAYERS`
Format:

- `%0:d` Count players with scores in the selected recent period


#### `STAT_OVERVIEW_FUN_VIDEO_MISSING`
Format:

- `%0:d` Count songs without video

Some further explanations about the wildcards:

```
%x:[.y]z
```

Where `X` is the number of the wildcard,
`Y` is optional, it is the number of digits for deciaml numbers (Z=d). So, if y is 2 there and the number is only 0 to 9 there will be a zero added in front of the number.
`z` can be d for numbers and s for texts.

For the date thing in `STAT_OVERVIEW_RESET` you may use `%0:.2d` for the day and `%1:.2d` for the month.
