# Personal Browser: development and GitHub operations

## Established project decisions

- Native SwiftUI + WKWebView, iPhone 12 / iOS 18.4.1; no third-party browser fork.
- On 2026-10-26 the user authorized making `koyuuuuu/personal-browser` public after auditing source and Git history, to use free standard Actions runners. This supersedes earlier private-source restrictions. Keep credentials and browsing data out of all Git history, logs and assets. The separate `personal-browser-distribution` mirror remains binary/metadata only.
- Free allowance only. The user reported no registered payment method. Do not enable paid usage, add paid AI services, or change billing settings.
- The user wants the assistant to perform routine development, commits, CI dispatch, log inspection, fixes, and artifact retrieval without asking them to log into GitHub for each step. This does not authorize unrelated changes. Source publication is authorized by the later instruction above.

## Authentication and execution

- Reuse the connected GitHub tools. When their capabilities are insufficient, use the configured GitHub CLI authentication. Do not start `gh auth login` merely because an environment was resumed.
- Check access with a small repository read, such as `gh api repos/koyuuuuu/personal-browser --jq '{full_name,private}'`. Never print tokens, inspect credential values, or ask for passwords/PATs in chat.
- A 403 on one endpoint does not establish an expired login. Distinguish endpoint permissions, network failures, and actual authentication failure. Request reconnection only when existing authorized access is demonstrably unavailable.
- Prefer a commit based on the current remote tree and update the branch with an expected-head lease. Preserve concurrent user changes.
- The iOS workflow now runs automatically for app/build/distribution changes pushed to main, and also supports workflow_dispatch. Do not dispatch a duplicate build when a push run exists. Documentation-only changes do not build. Keep the tooling workflow manual. Do not introduce scheduled macOS builds or rebuild for weekly SideStore signing.

## Validation and delivery

- Python checks: `python3 -W error -m unittest discover -s scripts -p 'test_*.py'`.
- Project consistency: `python3 scripts/generate_project.py --check`. Regenerate after adding/removing Swift source files.
- Core: `swift test` where Swift is available. UIKit/SwiftUI/WebKit validation requires macOS CI.
- Native build: `gh workflow run ios.yml --repo koyuuuuu/personal-browser --ref main -f build_ipa=true`. Identify the run by its source SHA, inspect failures, and verify the successful artifact. Do not dispatch a build merely to test authentication or after documentation-only edits.
- Prefer the GitHub artifact download connector for retrieval. A CLI artifact download redirect can fail in a managed network even when repository API authentication works.
- Inspect the downloaded IPA using `scripts/inspect_ipa.py --unsigned --target-ios 18.4.1` and compare SHA-256 with `build-info.json`.
- Deliver a file reference or actual workspace file link supported by the client, together with the build result. A GitHub Actions URL is a fallback; private artifact browser downloads require GitHub login. Do not publish private files to avoid that login, or claim a temporary download URL is permanent.
- Keep artifacts for one day. Local workspace copies are also not guaranteed permanent; retain exact source SHA and hash so a build can be reproduced when needed.
- Do not rerun native CI for documentation-only changes. Report native validation against the actual tested source commit.

## Device boundary

Apple Account login, 2FA, USB trust, Developer Mode, VPN permissions, SideStore installation, and actual refresh acceptance require the user's device. On 2026-10-24 the user reported that the browser is usable on their iPhone. Treat installation and launch as user-reported success, not proof that every feature or long-term re-signing has passed. Do not ask them to repeat initial installation without a specific need.

See `docs/github-automation.ja.md` and `docs/operations.ja.md`.

## Versioned releases and rollback

- Follow `docs/versioning.ja.md`. Keep version tags fixed at the actual successfully tested source commit. Record marketing version, build number, source SHA, CI run, IPA SHA-256, and data schema.
- Preserve every delivered version's unsigned IPA and build records. Do not rely on one-day Actions artifacts or the lifetime of the workspace.
- Initial `v0.1.0` points to `438292f5622801bf56525381576b789f65e4d203`, build 6. Its exact IPA is under `v0.1.0/` on the private `ipa-archive` branch.
- Conversation-side Release asset upload returned 401 on uploads.github.com; CI publishes private assets with its own ephemeral GITHUB_TOKEN. Public publishing maps the BROWSER_DISTRIBUTION_TOKEN repository secret to the publisher's DISTRIBUTION_TOKEN environment variable, a fine-grained token scoped only to the dedicated public repository. Never request its value in chat; it belongs in the private repository Actions Secrets. The initial v0.1.0 remains on ipa-archive.
- Never merge `ipa-archive` into main or overwrite a historical version's files. Read its current head/tree before appending another version. Check binary/repository size before adding larger artifacts; do not introduce paid storage or public distribution.
- When reverting a delivered app, preserve the current source history; use the old release or a new corrective commit. Re-sign through the same Apple Account and bundle ID. Do not delete the installed app as a default step.
- App rollback is separate from on-device data rollback. Before any incompatible persistence change, implement and test a backup/migration plan. Do not claim that old apps can read newer data formats.

## Automatic updates and latest user data

- The user's explicit policy is to keep the latest bookmarks/history/settings while updating or rolling back app functionality. Never restore an old user-data snapshot just because app code is reverted.
- Preserve `local.personalbrowser.app`, the existing application-support path, default WebKit data store, and schema 1. Keep feature-specific additions outside browser.json if older apps must ignore them safely. Refuse incompatible schema/identity changes in the release pipeline.
- `scripts/check_data_compatibility.sh` builds v0.1.0 and current persistence code separately, and checks old → new → old → new reads/writes against the latest library data. This does not replace device acceptance for actual SideStore signing and sandbox retention.
- Release versions come from distribution/release.json; build numbers come from the iOS workflow run counter. Tags use vVERSION-build.NUMBER and bind to the tested source SHA. Published files are immutable.
- The private distribution branch contains derived metadata only. The public mirror may contain only README.md, source.json, icon.png (and a license), plus unsigned IPA Release assets. Do not copy the private source commit tree into it.
- App update notices are foreground-only, opt-in, and checked at most daily automatically. Disabling them stops future automatic checks and hides the notice. Refreshing signatures and installing a new app version remain separate SideStore operations.
- See docs/distribution.ja.md for one-time token setup and the feed URL. A missing token must be reported as incomplete public deployment, not a successful live feed.

## Browser 0.3 feature invariants

- Tab records are capped at 500. BrowserTab creates WKWebView lazily; never read every tab.webView when rendering settings or the overview. Use existingWebView/isLive to inspect residency. Keep media/PiP and active downloads out of eviction.
- WebSurface stays mounted across selected-tab changes. Do not detach or hide a playing WebView on scene backgrounding. The audio background mode does not guarantee every site's PiP behavior; require device verification for video regressions.
- Keep a share URL inside the presented route's payload, not in separately updated sheet state. UI tests verify the share sheet's copy cell and a second presentation.
- Favorites/folder metadata live in library-extras.json; feature preferences in features.json. Keep the shared browser.json schema 1 compatible with baseline bookmark/history code. Old builds still cap sessions at 12, so do not promise 500-tab preservation when downgrading to them.
- Never add unknown enum cases to the legacy BrowserSettings.actions persistence without an old-reader strategy. The existing toolbar reorder/add/delete editor remains available.
- Watch HTML's personal origin stays in on-device settings/history. Do not embed the user's private video-server hostname or tunnel credentials into the public IPA/feed. Use a single URLComponents query item named url to pass the selected video link. Both /watch and /watch.html are supported.
- Safari ZIP transfer reads selected library entries in memory, skips password files before decompression, caps input and expanded data at 20MB, validates CRC, and uses Apple's Compression framework. Run the deflated-ZIP test on macOS. Password management remains Apple Passwords/iCloud Keychain, as explicitly chosen by the user.
- This version uses original built-in ad-domain rules, not Brave's engine or a licensed external filter subscription. Make filtering scope clear and preserve the site-exception toggle. Do not silently import a third-party filter list without checking its license and the user's source-selection preference.

## Browser 0.4 presentation, previews and connection rules

- Keep WebSurface's identity while animating tab changes. Never restore the old tab-added toast as a substitute for the requested transition. The next swipe beyond the last tab creates a new tab only below the 500-tab limit.
- Landscape starts with chrome hidden. Reverse scrolling reveals a compact top row. Preserve an accessible restore handle when manually hiding all chrome. Portrait uses the existing BrowserSettings toolbarPosition. SwiftUI persistentSystemOverlays requests home-indicator auto hiding; do not promise control over iOS's transient display or use private APIs.
- presentation.json stores new layout, crop, font, audio, and address-side settings separately from 0.3's features.json. Preserve missing-key defaults when extending the new file. Debounce slider writes and avoid resetting pageZoom when its value has not changed.
- Persist normal-tab previews and titles under Application Support/PersonalBrowser/tab-previews, with no TTL. Write each image generation before atomically switching the index. Load images on demand in the overview without creating every WKWebView. Never save private-tab previews. Closing a tab removes its own image, and a late snapshot must not recreate it.
- Certificate decisions must complete exactly once. Only an explicit checked confirmation persists an invalid-certificate exception. Scope it to normalized HTTPS origin, port, and the exact SHA-256 leaf fingerprint; a changed untrusted certificate requires another decision. Normal valid TLS remains under system validation. Never globally disable TLS, modify system trust, or add a blanket server-trust handler.
- A plain-HTTP fallback is offered only after TLS failure for loopback/private IPv4/.local, with an explicit unencrypted-connection explanation. Save the origin preference only when checked. Do not silently downgrade Internet sites. Store exceptions in on-device security-exceptions.json, not in source, release metadata or feeds. Include the local-network purpose string, with no extra entitlements.
- scripts/test_local_server.py supplies loopback-only HTTP, self-signed HTTPS and audio fixtures for native UI tests. Certificate keys are generated in a temporary CI directory, cleaned on exit and never uploaded. The tests must cover checked and unchecked certificate choices across restart and HTTP fallback, not contact the user's LAN.
- Background audio retains existing media views and uses public audio-session/background capabilities. Respect explicit pause, avoid activating audio for muted media, and do not claim that site/DRM/iOS limits are eliminated. Verify controlled audio without PiP in native tests and report device acceptance separately.

## 0.4.1 user-requested regression rollback

The latest user instruction overrides the old animation/restore-handle rules: no horizontal page slide, no visible restore arrows. Restore bars with a downward swipe and an accessibility action. Portrait uses build 14 spacing and bottom safe area. Media state script and audio-session behavior are reverted to build 14; do not reintroduce 0.4 background suspend/resume or session reconfiguration without a separately requested improvement. Never snapshot active media or inactive/transparent/background pages. Keep snapshotting views opaque until their request completes. Tile images and cards must have explicit grid widths, including after rotation. Close and reflow in one animation transaction without a deferred timer.

## 0.4.2 interaction updates

The user now requests interactive horizontal transitions specifically for address-bar swipes. Keep WebSurface itself stationary and mounted; animate noninteractive preview overlays only. Plus/menu tab creation still has no horizontal page slide. No restore arrows. Both portrait and landscape chrome follow deliberate finger direction; deceleration/bounce/layout changes never reveal bars. Keep the build 14 media policy.

Tab overview uses a native collection with immediate diffable removal at the horizontal swipe threshold. Cache decoded preview images; do not decode JPEGs per gesture frame. Delay disk cleanup to the normal save flush, never the visible removal. Expanded toolbar actions (including 5% zoom) are persisted in toolbar.json, leaving legacy enum arrays in browser.json/presentation.json readable by previous builds. History grouping is presentation-only, in local calendar morning/afternoon periods.

## 0.5 link routing, favorites and suggestions

- The user accepted 0.4.2 build27 as a rollback baseline. Retain its immutable tag/IPA; keep latest favorites and order readable by that build. The compatibility runner covers the library-extras.json round trip in addition to legacy bookmarks/history.
- mybrowser://open?url= is the free-signing external entry point. Validate and decode once, open a new tab, keep bundle identity. No managed default-browser entitlement, app groups or extensions are added.
- Universal-link preferences are local to this browser, never described as an iOS-wide setting. Use public APIs only, preserve POST/download semantics, and bound safe GET/HEAD interruption retries. Link choices live in link-preferences.json.
- Search suggestions are opt-in and normal-home-only; no requests in private tabs. Use ephemeral no-cookie sessions, debounce/cancel requests, and tolerate provider failures. Preferences live in search-preferences.json, not legacy BrowserSettings.
- Keep per-frame address-swipe state in the preview overlay. Freeze decoded images at gesture start, use an opaque overview-colored 4pt gap, and keep WebSurface mounted. Plus/menu creation has no horizontal slide.
- Cold/background URL tests must exercise OS URL delivery, not pass URL text directly into the store. The loopback CI fixture invokes simctl with three fixed cases; never accept arbitrary shell commands or user URLs there.

## Mandatory author privacy and rewritten IDs

The user explicitly authorized rewriting every branch/tag to remove personal author/committer email before publication. Use `266257694+koyuuuuu@users.noreply.github.com` for BOTH author and committer of every future commit/tag. Set repository-local user.name/user.email, and pass this identity explicitly to API commit creation. Do not use connector create_commit with its default author, which previously used a personal account email. Do not commit a mailmap containing the old address. Before pushing, inspect every new commit/tag identity and changed file for personal emails.

`distribution/history-rewrite.json` maps original source IDs to sanitized IDs and records original immutable build-info/IPA digests. This authorized identity rewrite supersedes the old instruction not to move historical tags for this migration only. App/core/test trees of delivered tags are unchanged; do not replace delivered IPA or build-info assets. Use sanitized baseline SHAs for compatibility checks. Preserve this correspondence in future release verification.
