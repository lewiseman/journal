# More: the inside cover

More brings together the account, appearance and connections. The body uses the
app's normal surface color. Bookcloth texture is confined to the account
card; soft ink washes sit behind the menu illustrations. These small material
details sit alongside Diary's pages, Notes' ink strokes and Flow's loose thoughts.

Start directly with useful content. There is no masthead, slogan, section label,
numbering or decorative footer. Text names a destination, describes a control or
shows the current account/connection state.

Only More and its account bookplate use the new treatment. Destination pages
retain their existing presentation.

## Reusing the style

- `MoreSurface` supplies the app's unchanged surface color. Use it behind the
  safe area and scrollable content of a future detail page.
- `MoreBookcloth` supplies the weave and stitched edge inside the account card.
  Keep this material clipped to the card rather than extending it over a page.
- `MorePalette.of(context)` supplies ground, paper, ink, muted ink, accent, rules
  and cloth. Colors follow the active accent and brightness. Body and display
  text inherit the user's selected font.
- `MoreIndexEntry` supplies a ruled navigation entry with optional descriptive
  text or connection status and a generated transparent image over a small ink wash.
  The entire entry is tappable.

Appearance uses an artist's color-sample set; Local QVAC uses a handcrafted
compute module with a geometric Q core. The full-color cutouts share the app's
navigation artwork palette and work on both light and dark surfaces. See
[the production assets and exact prompts](more-artwork.md).

Keep content in a centered column of at most 620 logical pixels, with roughly
28–32 pixels of side space. Use fine rules, restrained square corners and open
spacing. Reserve framed paper for account identity or another focused object.
The surrounding rules and washes inherit the accent. Images retain their
painted colors and disappear when large text calls for a simpler layout.

The expanded account card places an 84-pixel avatar at the top center, with the
name and account email centered beneath it. On collapse, the avatar moves left
and the identity becomes a compact row. The account keeps its existing
authentication and sync providers and account sheet. The compact strip expands
on tap, with instant movement when reduced
motion is enabled. Text-aware geometry keeps the account identity from
overflowing as text size increases.

## Verification

`test/more_page_test.dart` covers navigation, collapse/expand, signed-in and
signed-out states, logout, account reset review, dark mode, 320-pixel screens at
2× text scale and wide layouts. Set `MORE_CAPTURES=true` with `--dart-define` to
write rendered previews to `/tmp/journal-more-*.png`. The existing sync-card,
account-sheet and account-reset tests cover account behavior independently.
