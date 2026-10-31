#!/usr/bin/env python3
"""Select expensive checks from actual source changes; never select the full UI suite."""
import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# One representative scenario per behavior, rather than overlapping smoke tests.
AREAS = {
    "audio-mixing": ["testConcurrentAudioPreferenceAndRealPlayersAcrossTabs"],
    "selection-search": ["testSelectedTextSearchOpensAnAdjacentNewTab"],
    "external-links": ["test00ExternalURLColdLaunchBackgroundAndInvalidInput"],
    "tab-navigation": ["testNewTabPlacementAndViewedTabBackForward"],
    "blocking": ["testAdBlockingCanBeConfigured"],
    "tabs": ["testSwipeClosingGridReflowsAndRemainsUsableAfterRepeatedDeletions", "testOverviewOpensAtLastActiveTab"],
    "chrome": ["testLandscapeSwipeKeepsControlsWorkingAndTilesStayInsideWindow", "testPortraitForwardScrollHidesBarsAndBottomBounceDoesNotReveal"],
    "home": ["testLandscapeHomeWithCroppedBackgroundKeepsEveryChromeControlTappable"],
    "favorites": ["testFavoriteDragReordersAndSettingsEditsLatestDataAfterRestart"],
    "library": ["testFavoriteHomeAndBookmarkFolders", "testHistoryFoldersSupportSingleAndHalfDayDeletionAndAddressSuggestions"],
    "settings": ["testAddressSideActionsAndTabSizeCanBeConfigured", "testZoomToolbarButtonsChangeByFivePercentAndPersist"],
    "links": ["testOrdinaryLinkAndFormStayInBrowserWithoutFrameInterruption", "test00ExternalURLColdLaunchBackgroundAndInvalidInput"],
    "security": ["testRememberedCertificateIsReusedAfterRestart", "testUncheckedCertificateIsAskedAgainAfterRestart", "testPlainLocalHTTPServerIsOfferedAfterTLSFailure"],
    "previews": ["testNormalPreviewSurvivesProcessRestartWithoutLoadingThePage"],
    "sharing": ["testShareSheetContainsActionsRatherThanBlankContent"],
    "updates": ["testUpdateNotificationPreferenceCanBeTurnedOnAndOff"],
    "search": ["testHomeSearchSuggestionsCanBeEnabledAndDisabled"],
    "launch": ["testWebKitRendersAndExecutesOfflinePage"],
}
PATH_AREAS = {
    "App/BrowserViews.swift": ["chrome", "home"],
    "App/TabGridView.swift": ["tabs"], "App/TabOverview.swift": ["tabs"],
    "App/HomePageView.swift": ["home", "favorites"], "App/FavoritesSettingsView.swift": ["favorites"],
    "App/LibraryView.swift": ["library"], "App/SafariImport.swift": ["library"],
    "App/SettingsView.swift": ["settings"], "App/FeatureSettingsView.swift": ["blocking"],
    "App/PresentationSettingsView.swift": ["settings"], "App/ContentBlocking.swift": ["blocking"],
    "App/PersonalBrowserApp.swift": ["launch", "links"], "App/Info.plist": ["launch", "links"],
    "App/SiteIconLoader.swift": ["favorites"],
    "App/AudioMixingController.swift": ["audio-mixing"],
    "App/AudioMixingSettingsView.swift": ["audio-mixing"],
    "App/SelectedTextWebView.swift": ["selection-search"],
    "App/SelectedTextSearch.swift": ["selection-search"],
    "Sources/BrowserCore/TextSearch.swift": ["selection-search"],
    "Sources/BrowserCore/BlockingRules.swift": ["blocking"],
    "Sources/BrowserCore/SiteIconPolicy.swift": ["favorites"],
    "App/ConnectionPrompt.swift": ["security"], "App/SystemSharing.swift": ["sharing"],
    "App/UpdateChecker.swift": ["updates"], "App/UpdateSettingsView.swift": ["updates"],
    "App/HomeSearchSuggestions.swift": ["search"],
    "Sources/BrowserCore/LibraryExtras.swift": ["favorites", "library"],
    "Sources/BrowserCore/LibraryTransfer.swift": ["library"],
    "Sources/BrowserCore/HistoryPresentation.swift": ["library"],
    "Sources/BrowserCore/PresentationPreferences.swift": ["chrome", "settings"],
    "Sources/BrowserCore/AddressBarAction.swift": ["tab-navigation"],
    "Sources/BrowserCore/TabSelectionHistory.swift": ["tabs", "tab-navigation"],
    "Sources/BrowserCore/ToolbarCompatibility.swift": ["tab-navigation"],
    "Sources/BrowserCore/TabPreviewStore.swift": ["previews"],
    "Sources/BrowserCore/LinkRouting.swift": ["external-links"],
    "Sources/BrowserCore/ConnectionSecurity.swift": ["security"],
    "Sources/BrowserCore/SearchSuggestions.swift": ["search"],
    "Sources/BrowserCore/UpdateFeed.swift": ["updates"],
}
DATA_PATHS = {
    "Sources/BrowserCore/Models.swift", "Sources/BrowserCore/SnapshotStore.swift",
    "Sources/BrowserCore/LibraryExtras.swift", "Sources/BrowserCore/LibraryTransfer.swift",
    "Sources/BrowserCore/BrowserArchive.swift", "Sources/BrowserCore/PresentationPreferences.swift",
    "Sources/BrowserCore/ToolbarCompatibility.swift", "scripts/toolbar_compatibility_runner.swift",
    "scripts/check_data_compatibility.sh", "scripts/compatibility_runner.swift",
    "scripts/favorites_compatibility_runner.swift",
}
ARCHIVE_PATHS = {
    "scripts/publish_release.py", "scripts/distribution.py", "scripts/inspect_ipa.py",
    "scripts/verify_delivery.py",
    "distribution/history-rewrite.json", "docs/validation-2026-10-22.json",
}
STORE_DATA_METHODS = {
    "init", "restore", "loadAdditionalData", "saveAdditionalData", "captureSession", "scheduleSave",
    "flush", "recoverStorage", "importPages", "addBookmark", "deleteBookmarks", "updateBookmark",
    "deleteBookmark", "reorderBookmarks", "deleteHistory", "clearHistory", "updateSettings",
    "addFavorite", "deleteFavorite", "updateFavorite", "saveFavorite", "moveFavorite", "reorderFavorites",
    "createFolder", "updateFolder", "deleteFolder", "moveFolders", "moveBookmark",
}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf-8")


def content(ref, path):
    result = subprocess.run(["git", "show", f"{ref}:{path}"], cwd=ROOT, capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else ""


def methods(source):
    # BrowserStore/test methods are top-level members, indented four spaces.
    # Include the preamble so property/init changes do not escape review.
    pattern = r"^    (?:(?:private|fileprivate|public|static|override|convenience)\s+)*(?:func\s+(\w+)|(?P<init>init)\s*\()"
    matches = list(re.finditer(pattern, source, re.M))
    result = {"preamble": source[:matches[0].start()] if matches else source}
    for i, match in enumerate(matches):
        name = match.group(1) or "init"
        end = matches[i + 1].start() if i + 1 < len(matches) else len(source)
        result[name] = result.get(name, "") + source[match.start():end]
    return result


def changed_methods(before, after):
    old, new = methods(before), methods(after)
    return {key for key in old.keys() | new.keys() if old.get(key) != new.get(key)}


def plan(changed, store_changes=(), ui_changes=(), tab_changes=None, pending_app_paths=None, chrome_changes=None):
    changed = set(changed)
    areas = set()
    for path in changed:
        if path == "App/SettingsView.swift" and "App/AudioMixingSettingsView.swift" in changed:
            areas.add("audio-mixing")
        else:
            areas.update(PATH_AREAS.get(path, ()))
    selection_context = bool(changed & {"App/SelectedTextWebView.swift", "App/SelectedTextSearch.swift"})
    if "App/BrowserChrome.swift" in changed:
        action_methods = {"disabledAddress", "performAddress", "perform", "actionButton"}
        if selection_context and chrome_changes is not None and set(chrome_changes) <= {"viewport"}:
            areas.add("selection-search")
        elif chrome_changes is not None and set(chrome_changes) <= action_methods:
            areas.add("tab-navigation")
        else:
            areas.update(["chrome", "search"])
    if "App/BrowserTab.swift" in changed:
        names = set(tab_changes or ())
        if tab_changes is None:
            areas.update(["links", "security", "previews"])
        else:
            if names & {"preamble", "init", "createWebView", "releaseWebView", "loadTestFixture"}: areas.add("launch")
            if "configureBlocking" in names: areas.add("blocking")
            if names & {"webView", "load", "show", "loadInBrowser", "openRelatedApplication"}: areas.update(["links", "security"])
            if "capturePreview" in names: areas.add("previews")
            if any(name.startswith("scrollView") for name in names): areas.add("chrome")
    store_changes = set(store_changes)
    if "App/BrowserStore.swift" in changed:
        if store_changes & {"preamble", "init"}:
            areas.update(["launch", "tabs"])
        for name in store_changes:
            if name == "makeTab" and selection_context and store_changes <= {"makeTab", "receiveExternalURL"}:
                areas.add("selection-search")
            elif re.search(r"Tab|^select$|^close$|^reopen", name): areas.update(["tabs", "tab-navigation"])
            if re.search(r"Favorite", name): areas.add("favorites")
            if re.search(r"Bookmark|Folder|History|importPages", name): areas.add("library")
            if re.search(r"Chrome|Landscape|Presentation", name): areas.add("chrome")
            if re.search(r"Preview", name): areas.add("previews")
            if re.search(r"ExternalURL", name): areas.add("external-links")
            if re.search(r"^navigate$|^open$|LinkPreference", name): areas.add("links")
            if re.search(r"Search|^search$", name): areas.add("search")
    tests = {test for area in areas for test in AREAS[area]}
    # Selection search already launches and renders a real WKWebView fixture.
    if areas & {"selection-search", "audio-mixing"}:
        tests.difference_update(AREAS["launch"])
    allowed = {test for group in AREAS.values() for test in group}
    tests.update(set(ui_changes) & allowed)
    if "UITests/BrowserUITests.swift" in changed and any(not x.startswith("test") for x in ui_changes):
        tests.update(AREAS["launch"])
    return {
        "areas": sorted(areas), "ui_tests": sorted(tests),
        "compatibility": bool(changed & DATA_PATHS or store_changes & (STORE_DATA_METHODS | {"preamble"})),
        "verify_archives": bool(changed & ARCHIVE_PATHS),
        # CI-only changes still build/inspect an IPA, but do not publish an unchanged app.
        "publish": any(p.startswith(("App/", "Sources/")) or p in {"Package.swift", "PersonalBrowser.xcodeproj/project.pbxproj", "distribution/release.json"} for p in (changed if pending_app_paths is None else pending_app_paths)),
        "changed_paths": sorted(changed),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--output", default="build/verification-plan.json")
    parser.add_argument("--github-output")
    args = parser.parse_args()
    base = args.base
    if not base or set(base) == {"0"}:
        base = git("rev-parse", f"{args.head}^").strip()
    paths = git("diff", "--name-only", "--no-renames", base, args.head).splitlines()
    changes = {}
    for path in ("App/BrowserStore.swift", "UITests/BrowserUITests.swift", "App/BrowserTab.swift", "App/BrowserChrome.swift"):
        changes[path] = changed_methods(content(base, path), content(args.head, path)) if path in paths else set()
    result = plan(paths, changes["App/BrowserStore.swift"], changes["UITests/BrowserUITests.swift"], changes["App/BrowserTab.swift"], chrome_changes=changes["App/BrowserChrome.swift"])
    delivered_tags = git("tag", "--list", "v*-build.*", "--sort=-version:refname").splitlines()
    if delivered_tags:
        # A test/build fix after a failed app run must still deliver the pending
        # app change. Test SELECTION stays scoped to this push, independently.
        pending = git("diff", "--name-only", "--no-renames", delivered_tags[0], args.head).splitlines()
        result["publish"] = plan([], pending_app_paths=pending)["publish"]
        result["publication_base"] = delivered_tags[0]
        if result["publish"]:
            # Keep unresolved app-area checks in scope until the pending app is
            # delivered. A test-only follow-up must not accidentally drop a
            # previously failed feature check from the publication gate.
            app_pending = [p for p in pending if p.startswith(("App/", "Sources/"))]
            for path in ("App/BrowserStore.swift", "App/BrowserTab.swift", "App/BrowserChrome.swift"):
                if path in app_pending:
                    changes[path] = changed_methods(content(delivered_tags[0], path), content(args.head, path))
            scoped = plan(set(paths) | set(app_pending), changes["App/BrowserStore.swift"],
                          changes["UITests/BrowserUITests.swift"], changes["App/BrowserTab.swift"], chrome_changes=changes["App/BrowserChrome.swift"])
            result["areas"] = scoped["areas"]
            result["ui_tests"] = scoped["ui_tests"]
            result["compatibility"] = scoped["compatibility"]
    if "distribution/release.json" in paths:
        old = json.loads(content(base, "distribution/release.json") or "{}")
        new = json.loads(content(args.head, "distribution/release.json"))
        result["verify_archives"] |= any(old.get(k) != new.get(k) for k in ["bundle_id", "data_schema", "public_repository"])
    target = ROOT / args.output
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=2) + "\n")
    if args.github_output:
        with open(args.github_output, "a") as output:
            for key in ("compatibility", "verify_archives", "publish"):
                output.write(f"{key}={str(result[key]).lower()}\n")
            output.write("ui_tests=" + ",".join(result["ui_tests"]) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
