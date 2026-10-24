# Song filter overlay

The overlay uses the normal theme sections and inheritance. Modern defines the
stacked layout; Deluxe inherits it. Other themes can override these sections:

| Section | Controls |
| --- | --- |
| `SongJumptoFilters` | `RowSpacing`, the vertical distance between the three visible rows |
| `SongJumptoSelectSlideType` | First row's category selector, including arrows and text |
| `SongJumptoButtonSearchText` | First row's input position, size, texture and selection appearance |
| `SongJumptoButtonAdd`, `SongJumptoButtonClear`, `SongJumptoButtonDone`, `SongJumptoButtonLock` | Action buttons, independently positioned |
| `SongJumptoTextFound` | Result count |
| `SongJumptoStatic*`, `SongJumptoBackground`, `SongJumptoText*` | Dialog background, decoration and heading |

Each button supports the usual `Texts` and `...Text1` sections for font, size,
color, alignment and text offsets. Input text and action captions are filled by
the game. Rows are removed using Backspace when their input is empty. The second and third row
reuse the first row's controls, offset by `RowSpacing`; extra rows scroll through
these three slots. Mouse hit areas follow the themed control bounds.

Themes without `SongJumptoFilters` receive a compatibility layout derived from
their existing search controls. Adding that section opts into explicit layout:
set the input, result count, actions and dialog background to fit the rows.
Set `AutoHeightStatic` to the 1-based dialog background index to shrink it
when fewer than three rows are present. The result count and Add/Done/Lock
buttons move up with the hidden rows; Clear stays in the header. Leave it at
0 for a fixed layout. Modern uses the plain dialog background without a divider.

CenterVertical=1 in SongJumptoFilters centers the complete panel after its
height is calculated. The Done button is unused: Enter from an input and Escape
return to song selection. Lock state is shown with a vector padlock inside the
Lock button's themed bounds.
