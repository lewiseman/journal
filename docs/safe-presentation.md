# H01 — Safe optional presentation

H01 styles a saved note body on the current device. It preserves source bytes,
existing paragraphs, Markdown structure and block order. Diary entries are not
styled: the diary shows plain text only, without Markdown.
The optional computer still uses Electron 45.0.0, QVAC SDK 0.22.0 and its pinned
Qwen2.5 0.5B Instruct Q4_K_M model. No model is downloaded or replaced by H01.

## Use and recover

Save a note, then open its wand menu → **Presentation**. Describe an optional styling request
and choose **Generate presentation**. Compare the exact selectable original with
the styled preview, then explicitly accept or reject it. Nothing is submitted
until Generate. Editing continues to use the original text/Markdown.

Accepted styling appears in the reader and survives app restart without the
computer. **Revert to original** disables it immediately. The presentation screen
also exposes its exact saved source snapshot for inspection/copy and explicitly
confirmed removal. A changed/deleted source disables rendering of that derivative;
it cannot replace newer words. The original snapshot remains available until
replacement/removal/reset.

The small model has limited capability. An unconstrained real-QVAC trial omitted
the required CSS field. H01 uses the installed SDK's per-request `json_schema`
grammar to require the envelope and fixed source-slot HTML. CSS remains a model
proposal, independently checked by Flutter. Incompatible/truncated responses fail
closed with an explicit retry. Successful basic spacing is not evidence of broad
styling quality, intent following, language coverage or sophisticated design.

## Rendering boundary

There is no WebView, JavaScript engine, DOM renderer, URL launcher, native bridge,
or model-controlled asset loader. The already installed `html` 0.15.7, `csslib`
1.0.2 and `markdown` 7.3.1 packages are direct pinned dependencies. Parser APIs were
checked against those installed sources and their primary documentation:
[HTML](https://pub.dev/packages/html/versions/0.15.7),
[CSS](https://pub.dev/packages/csslib/versions/1.0.2),
[Markdown](https://pub.dev/packages/markdown/versions/7.3.1).

Flutter assigns temporary `b0`…`b15` IDs to immutable source blocks. Supported HTML
is one attribute-free `<article>` containing empty
`<section data-source="b0" class="s0"></section>` slots, exactly once each in
source order. Model text, nested elements and other attributes are rejected.
The compiler translates accepted syntax to a typed document; widgets never
consume the generated HTML/CSS directly.

CSS allows at most eight unique `.s0`…`.s7` rules, with six unique declarations
each. The current generation grammar uses `.s0` for all source blocks. There is
no cascade, combinator, pseudo-element, function, escape, comment or `!important`.

| Property | Allowed values |
| --- | --- |
| `font-size` | `1em`, `1.125em`, `1.25em` |
| `font-weight` | `400`, `500`, `600`, `700` |
| `font-style` | `normal`, `italic` |
| `line-height` | `1.4`, `1.6`, `1.8` |
| `margin-bottom` | `0`, `0.5em`, `1em`, `1.5em` |
| `padding-left` | `0`, `0.5em`, `1em` |

Every other declaration is rejected. Model output cannot hide, position, clip or
overlay content/controls or request colors, fonts, files or network resources.
Compilation runs in a killable isolate with a one-second deadline. Source is
bounded to 64 KiB, 16 blocks, 256 AST nodes and depth 16. The complete request is
at most 2,000 UTF-8 bytes, including block IDs and optional 240-byte intent;
oversized material is refused without truncation. Output is bounded to 4,096
bytes/768 tokens, with no partial result on token exhaustion.

Native rendering uses the existing Markdown AST/public builder with an offline
delegate. Links become inert text and images become alt-text placeholders.
Source HTML remains literal text. Source numbering/checkbox state is inert.
App theme ink/paper and already resolved fonts are inherited, with system fallback;
the renderer does not initiate font downloads. Native scaling, selection,
heading semantics and reading order are retained. Controls are native siblings.
Corrupt/unsupported stored documents and renderer failures show original text.
The existing unstyled Markdown reader retains its prior behavior.

**Copy original** returns exact source; selection copies rendered text. Search,
Drive JSON and existing backup/export paths continue to use source content.
There is no standalone styled HTML/PDF export in H01.

## Storage, roles and privacy

The existing single protected task slot is shared by summaries, note writing and
presentations. A typed source reference names the note, while old
summary/transformation handles and secure-storage keys remain compatible. Only temporary block IDs, their text and intent go to the paired
computer: no title, tags, attachments, journal IDs or unrelated entries. Exact
source/version snapshots stay in protected task storage, excluded from task
metadata. Existing signed/pinned transport, device attribution, cancellation,
expiry and acknowledgment behavior is reused.

One local ObjectBox `PresentationEntity` per source stores a validated typed
document, policy version, source reference/snapshot/revision, task ID, creation
time and enabled state. Replacing it replaces its older snapshot. This is local
application database protection, **not separate encryption**. It is excluded from
sync collections/outboxes and does not change source clocks or pending uploads.
Other devices receive ordinary source content without this device's styling.
Account reset clears presentation rows and protected task data.

Note revisions use the version vector and exact body. Acceptance rereads the live source and editing
role in an ObjectBox transaction. Stale/duplicate tasks are refused. Secondary
devices can review; accepting/reverting/removing requires existing edit rights.
Viewing/copying source does not bypass editing roles.

## Reproduce verification

```sh
# journal/
flutter analyze lib/modules/presentation lib/modules/notes lib/modules/diary \
  lib/modules/root/controllers/journal_account_reset_data.dart \
  test/presentation_test.dart integration_test/presentation_device_test.dart
flutter test test/presentation_test.dart test/note_transform_test.dart \
  test/note_summary_test.dart test/diary_day_content_test.dart \
  test/diary_page_test.dart test/diary_paper_curl_test.dart
flutter test
flutter test packages/sync_wise/test
flutter build apk --debug
flutter build ios --simulator --debug

# desktop/
npm test
npm run package
node scripts/verify-notes.cjs /absolute/new/empty/h01-evidence \
  /absolute/verified/model.gguf --presentation
```

The packaged two-phase harness uses synthetic note blocks and an isolated
encrypted vault, real signed/pinned TLS/QVAC, same-ID retry, companion restart,
retrieval and acknowledgment. It refuses a nonempty evidence directory. The
per-request grammar API was verified in the installed SDK's
`dist/examples/llamacpp-structured-output.js` and
`dist/src/client/api/completion-stream.js`; `required` and
`additionalProperties:false` are explicit because the SDK's `strict` option does
not implicitly tighten schemas. Flutter validation remains mandatory.

For mobile tests, provision a separate empty directory's `app-data/model.json`
with the verified model path, then launch the packaged companion with:

```sh
"out/Journal Companion-darwin-arm64/Journal Companion.app/Contents/MacOS/Journal Companion" \
  --connection-demo=/absolute/isolated/h01-mobile --demo-port=47928 \
  --recovery-phone-fixture

# journal/; repeat online on Android and an iPhone simulator
flutter test integration_test/presentation_device_test.dart -d DEVICE_ID \
  --no-uninstall --dart-define-from-file=/absolute/isolated/h01-mobile/device-config.json

# Stop that isolated companion, then rerun on each target without uninstalling.
flutter test integration_test/presentation_device_test.dart -d DEVICE_ID \
  --no-uninstall --dart-define=H01_OFFLINE=true
```

This reuses the test-only synthetic enrollment fixture rather than claiming
production pairing-UI coverage. Keys, protected slots and ObjectBox directories
are separate from ordinary app data. Never commit `device-config.json` or use
the fixture with a personal vault. The offline phase inspects both persisted
derivatives after a new app process, renders while the companion is stopped,
reverts locally and clears synthetic data/trust. Rebuild the normal Android
entry point afterward and install with `adb install -r`; do not uninstall or
wipe user data. Runtime evidence and remaining coverage limits are recorded in
`safe-presentation-evidence.json`.

The recorded run has 341 passing Flutter tests and the same two pre-existing
onboarding large-text overflows, plus 32 passing companion tests and 24 passing
sync package tests. All nine H01 checks pass, including reactive source/deletion
fallback, note-paper contrast and matching live/curl diary prose. Focused analysis
has no issues; full analysis retains five existing informational lints elsewhere.
Real QVAC online and companion-stopped restart demonstrations passed on Samsung
SM-S928B / Android 17 and iPhone 17 Pro / iOS 26.5 simulator. Eight injected
adversarial cases and renderer-failure recovery also passed on each target with
zero renderer-created network clients. Normal app entry points were restored
without wiping data, and disposable test trust/vaults were removed.

[Android presentation screenshot](safe-presentation-android.png) shows the
accepted rendition and source/reversion controls. Physical iPhone, human screen
reader review, broad styling quality and simultaneous WAN-disconnected inference
remain unverified; injected failures are not represented as observed model attacks.
