# More: the inside cover

More is the journal's inside cover: a place for the account, appearance
and connections. Its bookcloth substrate and compact account bookplate sit alongside
Diary's pages, Notes' ink strokes and Flow's loose thoughts.

Start directly with useful content. There is no masthead, slogan, section label,
numbering or decorative footer. Text names a destination, describes a control or
shows the current account/connection state.

Only More and its account bookplate use the new treatment. Destination pages
retain their existing presentation.

## Reusing the style

- `MoreSurface` supplies the warm woven ground and stitched binding edge. Use it
  behind the safe area and scrollable content of a future detail page.
- `MorePalette.of(context)` supplies ground, paper, ink, muted ink, accent, rules
  and cloth. Colors follow the active accent and brightness. Body and display
  text inherit the user's selected font.
- `MoreIndexEntry` supplies a ruled navigation entry with optional descriptive
  text or connection status and a larger illustration. The entire entry is tappable.

Keep content in a centered column of at most 620 logical pixels, with roughly
28–32 pixels of side space. Use fine rules, restrained square corners and open
spacing. Reserve framed paper for account identity or another focused object.
Illustrations inherit the palette and disappear when space or large text calls
for a simpler layout.

The account keeps its existing authentication and sync providers and account
sheet. Its compact strip expands on tap, with instant movement when reduced
motion is enabled. Text-aware geometry keeps the account identity from
overflowing as text size increases.

## Verification

`test/more_page_test.dart` covers navigation, collapse/expand, signed-in and
signed-out states, logout, account reset review, dark mode, 320-pixel screens at
2× text scale and wide layouts. Set `MORE_CAPTURES=true` with `--dart-define` to
write rendered previews to `/tmp/journal-more-*.png`. The existing sync-card,
account-sheet and account-reset tests cover account behavior independently.
