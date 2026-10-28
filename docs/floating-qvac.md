# Floating QVAC

The app-wide assistant uses `assets/images/more_local_qvac.png` and the existing
`companionControllerProvider`. It adds no connection probes, network polling, or
storage. Its green check, amber connecting state, and muted disconnected badge
reflect the companion's live transport phase, not model readiness.

- The floating artwork has a close paper sticker edge and soft shadow following
  its transparent silhouette, with a small status badge and no circular backing.
- Tap opens an expandable contextual sheet; hold opens the local AI companion.
- In Diary, the sheet offers Day details (title, mood and themes), Microphone,
  and Presentation for the selected day. Presentation chooses a saved text entry
  and opens its styling tools within the same sheet; it is disabled on empty
  days. These actions no longer appear on the diary card. Existing edit and
  secondary-device restrictions apply.
- Diary Microphone closes the QVAC sheet and opens the full voice conversation
  page for the selected day. Leaving voice returns directly to the diary.
- In a single note, a compact illustrated toolbox groups actions by purpose:
  Edit, Add, and Appearance. Short labels pair with custom paper drawings; lone
  choices use a full-width card. New notes offer starting templates, scanning,
  and backgrounds that return directly to the unsaved draft. The menu starts
  with its tools, without branding, a note-name row, status text, or a close button;
  dragging down dismisses the sheet.
- Note feature pages share a warm paper frame, tool illustration, and visual
  Choose → Create → Review trail. Back remains visible while content scrolls.
  Opening a note tool expands the sheet to full height, including draft tools;
  the toolbox initially opens at its compact height. Expansion respects reduced motion.
  Writing help uses illustrated actions, a Choose → Preview → Use stepper,
  whole-note previews, and optional read-aloud controls. Tone uses presets,
  with no typing or passage selection. Presentation modes use icon-led choices;
  background scenes and template purposes offer visual starting points. The
  pages omit About and sharing disclosures and earlier-version actions. Results
  still require explicit acceptance, and title/tag Undo retains its behavior.
- Saved-note tools require the editor to be closed with the note saved. Scanning
  and background generation retain their primary-device restriction. Tool cards
  switch to a single column on narrow screens or with large text, and the note
  palette adapts to dark mode. All note pages use the sheet's scroll controller.
- The sheet and its page content share scrolling: scroll up to fill the page,
  then continue through the content. Drag or tap the handle to resize it.
- Every page sheet has a Local AI settings shortcut above its surface, in the
  transparent area. It fades away as the sheet fills the page and returns when
  collapsed. Note sheets show only a settings icon. The shortcut opens the
  existing local companion settings.
- Drag to move, release to snap to an edge, or release in the bottom dismissal
  area to hide it for the rest of the app session.
- On More, the same image moves into the original illustration slot and follows
  its composited layer while scrolling. It floats again if the slot scrolls out
  of view or under the pinned account header. Dismissal restores the original
  static More image and keeps the floating assistant closed when changing pages.
- Onboarding, the companion route, their unmarked child routes, and modal
  dialogs/sheets hide the assistant. Account reset removes the entire host.
- Safe areas, the keyboard, rotation, large text, and reduced motion are handled.
  Animation ticks rebuild only the assistant; settled states have no ticker.

`QvacAssistantHost` wraps the app Navigator. `QvacAssistantObserver` must be
recreated when that Navigator is replaced. `QvacAssistantPage` supplies the
current page label and optional exclusion; a pushed page can register its own
label with that wrapper. Root tabs already supply Diary, Notes, Flow, and More.
Unmarked pushed destinations use a generic placeholder. `QvacAssistantContent`
registers a page's sheet builder by route and label, so retained tabs supply
tools only while active. New page content must use the supplied scroll controller.

Tests: `test/qvac_assistant_test.dart` covers navigation, status, gestures,
dismissal, animation interruptions, scrolling, and adaptive layouts.
`test/more_page_test.dart` also exercises docking in the real More page.
`test/diary_assistant_test.dart` exercises selected-day tools, shared scrolling,
metadata saving, microphone layout and secondary-device restrictions.
`test/note_assistant_test.dart` covers every note tool, shared scrolling, editor
refresh and Undo, draft restrictions, secondary devices, and back navigation.
