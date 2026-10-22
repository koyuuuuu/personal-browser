# Personal Browser: development and GitHub operations

## Established project decisions

- Native SwiftUI + WKWebView, iPhone 12 / iOS 18.4.1; no third-party browser fork.
- Private repository: `koyuuuuu/personal-browser`. Keep it private.
- Free allowance only. The user reported no registered payment method. Do not enable paid usage, add paid AI services, or change billing settings.
- The user wants the assistant to perform routine development, commits, CI dispatch, log inspection, fixes, and artifact retrieval without asking them to log into GitHub for each step. This does not authorize unrelated changes or publishing the source.

## Authentication and execution

- Reuse the connected GitHub tools. When their capabilities are insufficient, use the configured GitHub CLI authentication. Do not start `gh auth login` merely because an environment was resumed.
- Check access with a small repository read, such as `gh api repos/koyuuuuu/personal-browser --jq '{full_name,private}'`. Never print tokens, inspect credential values, or ask for passwords/PATs in chat.
- A 403 on one endpoint does not establish an expired login. Distinguish endpoint permissions, network failures, and actual authentication failure. Request reconnection only when existing authorized access is demonstrably unavailable.
- Prefer a commit based on the current remote tree and update the branch with an expected-head lease. Preserve concurrent user changes.
- Both workflows currently use `workflow_dispatch`. The assistant should initiate necessary builds; the user does not need to open Actions and click Run workflow. Do not introduce scheduled macOS builds or rebuild for weekly SideStore signing.

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

Apple Account login, 2FA, USB trust, Developer Mode, VPN permissions, SideStore installation, and actual refresh acceptance require the user's device. The user will install SideStore after returning home. Do not request those steps while they are away or claim device acceptance is complete.

See `docs/github-automation.ja.md` and `docs/operations.ja.md`.
