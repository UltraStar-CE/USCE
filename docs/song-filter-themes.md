# Song filter overlay

The overlay uses the normal theme sections and inheritance. Modern defines the
stacked layout; Deluxe inherits it. Other themes can override these sections:

| Section | Controls |
| --- | --- |
| `SongJumptoFilters` | `RowSpacing`, the vertical distance between the three visible rows |
| `SongJumptoSelectSlideType` | First row's category selector, including arrows and text |
| `SongJumptoButtonSearchText` | First row's input position, size, texture and selection appearance |
| `SongJumptoButtonRemove` | First row's remove button |
| `SongJumptoButtonAdd`, `SongJumptoButtonClear`, `SongJumptoButtonDone`, `SongJumptoButtonLock` | Action buttons, independently positioned |
| `SongJumptoTextFound` | Result count |
| `SongJumptoStatic*`, `SongJumptoBackground`, `SongJumptoText*` | Dialog background, decoration and heading |

Each button supports the usual `Texts` and `...Text1` sections for font, size,
color, alignment and text offsets. Input text and action captions are filled by
the game. The remove caption comes from the theme. The second and third row
reuse the first row's controls, offset by `RowSpacing`; extra rows scroll through
these three slots. Mouse hit areas follow the themed control bounds.

Themes without `SongJumptoFilters` receive a compatibility layout derived from
their existing search controls. Adding that section opts into explicit layout:
set the input, result count, actions and dialog background to fit the rows.
The game does not resize the background or reposition the input/result count
for themes that define this section.
