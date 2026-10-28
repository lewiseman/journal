# Floating QVAC

The app-wide assistant uses `assets/images/more_local_qvac.png` and the existing
`companionControllerProvider`. It adds no connection probes, network polling, or
storage. Its green check, amber connecting state, and muted disconnected badge
reflect the companion's live transport phase, not model readiness.

- Tap opens a contextual placeholder sheet; hold opens the local AI companion.
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
Unmarked pushed destinations use a generic placeholder. Replace the placeholder
in `QvacAssistantSheet` as page-specific widgets become available.

Tests: `test/qvac_assistant_test.dart` covers navigation, status, gestures,
dismissal, animation interruptions, scrolling, and adaptive layouts.
`test/more_page_test.dart` also exercises docking in the real More page.
