# Personal Browser: development and GitHub operations

## Established project decisions

- Native SwiftUI + WKWebView, iPhone 12 / iOS 18.4.1; no third-party browser fork.
- Private source repository: `koyuuuuu/personal-browser`. Keep it private. The user explicitly approved publishing only unsigned IPAs, the required app icon, and SideStore source JSON to the separate public `koyuuuuu/personal-browser-distribution` repository. Never publish Swift source, private build logs, credentials, or browsing data there.
- Free allowance only. The user reported no registered payment method. Do not enable paid usage, add paid AI services, or change billing settings.
- The user wants the assistant to perform routine development, commits, CI dispatch, log inspection, fixes, and artifact retrieval without asking them to log into GitHub for each step. This does not authorize unrelated changes or publishing the source.

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
