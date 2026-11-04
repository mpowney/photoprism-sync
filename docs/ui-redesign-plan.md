# UI redesign plan (handoff for a new Copilot agent session)

Repository: `mpowney/photoprism-sync` (SwiftUI, iOS 17, iPhone-only today: `TARGETED_DEVICE_FAMILY = 1`).

## Starting a new agent session

1. Allow the host first: repo **Settings → Copilot → Cloud agent → Firewall → Custom allowlist**, add `developer.apple.com`. Org owners can set this at org level. Save it before starting the session.
2. Start the session from the repo's **Agents** tab (github.com/mpowney/photoprism-sync/agents), or from the Copilot CLI / VS Code against `mpowney/photoprism-sync`, on the branch that contains this file.
3. Suggested prompt:

   > Read `docs/ui-redesign-plan.md` in mpowney/photoprism-sync and implement it in a single PR. First fetch https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo and reconcile the plan with it (screen modes, fold/hinge, orientation, any named APIs). If any step needs a real device to verify, say so and split it into a separate PR. Ask for approval on each key update with mockup screenshots before implementing.

Context from the previous session: the Apple page could not be fetched (firewall), so its contents were not confirmed. Do not invent fold/posture APIs; use only what the page documents.

## Current state (from code review)

- `PhotoPrismSync/ContentView.swift`: `TabView` with Sync (one long `Form`) and Settings tabs. Calculate / Preview / Execute buttons are a Form section at the bottom.
- `PhotoPrismSync/Views/PreviewGridView.swift`: sheet, adaptive 120pt grid, rounded thumbnails with filename + size captions, no Done button, selection or detail view.
- Also: `Views/SettingsView.swift`, `Views/CriteriaFormView.swift`, `ViewModels/AppViewModel.swift`.

## Recommendations (each needs user approval via mockups)

1. **Navigation.** A tab bar is for top-level sections; a toolbar is for actions on the current screen, so they are not interchangeable. Remove the `TabView`; make Sync the root; add a gear button in the nav bar opening Settings. Reintroduce a tab bar only if real top-level sections are added.
2. **Bottom toolbar for actions.** Preview on the left, prominent primary action on the right (Calculate, then Upload/Download/Delete). Delete uses a destructive style plus a confirmation dialog. Remove the button section from the Form.
3. **Sync screen.** Summary card (item count, size, prepared time), compact progress/status bar above the toolbar, SF Symbol row icons, Dynamic Type, haptics on completion.
4. **Photos-style preview.** Edge-to-edge 3-column square grid with 1–2pt gaps and no captions; badges for video duration, Live Photo, and "already on server"; tap opens a full-screen pager with pinch-zoom and an info sheet; Select/Deselect so users can exclude items; sticky bottom bar "N selected · size" with a Sync button; Done in the top bar; lazy thumbnails with caching/prefetch.
5. **Adaptive / iPhone Duo.** Use a `NavigationSplitView` (criteria/actions sidebar, preview grid detail) when width is regular and a single stack when compact; drive by size classes, not device checks. Use system navigation and toolbar components so controls adapt to Duo's vertical layout, respect safe areas, and prefer an even number of grid columns in folded layouts. The HIG does not require an orientation lock or a device-family change.
6. **Polish.** Pull-to-refresh, empty states, first-run onboarding to sign-in, Dark Mode and VoiceOver checks, Photos permission explainer.

## PR strategy

Single PR for layout and interaction changes. Exception: custom hinge/fold behavior, including use of reserved regions, or anything that needs a real device should be a separate follow-up PR tested on hardware before merging. Suggested order within the PR: 1+2, 4, 5, 3+6.

## Notes

- Existing tests: `Tests/PhotoPrismSyncCoreTests` (core logic only; `swift test` on macOS). The UI cannot be built in the Linux sandbox, so state clearly what was not verified.

## Approved implementation scope

- The four mockup checkpoints were approved together before implementation.
- The sync screen now uses a settings toolbar action and system toolbar actions; regular-width layouts show criteria beside the preview, while compact layouts use a single stack.
- Preview items are selectable, with a square grid, a full-screen pager, pinch zoom, item information, and a selected-item count and size. The media model does not currently provide video duration or an “already on server” flag, so those badges are not shown.
- Custom hinge/fold handling and reserved-region adjustments remain out of scope until they can be validated on iPhone Duo hardware; deliver them in a separate follow-up PR if needed.
