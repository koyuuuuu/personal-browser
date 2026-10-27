#!/usr/bin/env python3
"""Generate a small deterministic Xcode project without external generators."""

import argparse
import hashlib
import json
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]


def identifier(label):
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()


def encode(value, indent=0):
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append("\t" * (indent + 1) + json.dumps(key) + " = " + encode(item, indent + 1) + ";")
        lines.append("\t" * indent + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (indent + 1) + encode(item, indent + 1) + ",\n" for item in value) + "\t" * indent + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)


def generate():
    objects = {}
    release = json.loads((ROOT / "distribution/release.json").read_text())

    def add(label, isa, **fields):
        key = identifier(label)
        objects[key] = {"isa": isa, **fields}
        return key

    groups = {}
    source_ids = {"app": [], "ui": []}
    for folder, kind in [("App", "app"), ("Sources/BrowserCore", "app"), ("UITests", "ui")]:
        children = []
        for path in sorted((ROOT / folder).glob("*.swift")):
            relative = path.relative_to(ROOT).as_posix()
            reference = add("file:" + relative, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=path.name, sourceTree="<group>")
            children.append(reference)
            source_ids[kind].append(add("build:" + relative, "PBXBuildFile", fileRef=reference))
        if folder == "App":
            children.append(add("file:Info", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>"))
            children.append(add("file:FilterResources", "PBXFileReference", lastKnownFileType="folder", path="FilterResources", sourceTree="<group>"))
            children.append(add("file:Assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Assets.xcassets", sourceTree="<group>"))
        groups[folder] = add("group:" + folder, "PBXGroup", children=children, path=folder, sourceTree="<group>")

    app_product = add("product:app", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="PersonalBrowser.app", sourceTree="BUILT_PRODUCTS_DIR")
    ui_product = add("product:ui", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path="PersonalBrowserUITests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    products = add("group:products", "PBXGroup", children=[app_product, ui_product], name="Products", sourceTree="<group>")
    root_group = add("group:root", "PBXGroup", children=[*groups.values(), products], sourceTree="<group>")

    def configurations(scope, common):
        configs = []
        for name in ["Debug", "Release"]:
            settings = dict(common)
            settings.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O"})
            if name == "Debug":
                settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) DEBUG"
                settings["ENABLE_TESTABILITY"] = "YES"
            configs.append(add(f"config:{scope}:{name}", "XCBuildConfiguration", buildSettings=settings, name=name))
        return add("configs:" + scope, "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

    project_configs = configurations("project", {
        "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
        "BROWSER_BUNDLE_ID": "local.personalbrowser.app",
        "BROWSER_UPDATE_SOURCE_URL": "https://raw.githubusercontent.com/" + release["public_repository"] + "/main/source.json",
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "SWIFT_STRICT_CONCURRENCY": "targeted", "ENABLE_USER_SCRIPT_SANDBOXING": "YES"
    })
    app_configs = configurations("app", {
        "PRODUCT_BUNDLE_IDENTIFIER": "$(BROWSER_BUNDLE_ID)", "PRODUCT_NAME": "$(TARGET_NAME)",
        "INFOPLIST_FILE": "App/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": release["version"], "CODE_SIGN_STYLE": "Automatic",
        "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"]
    })
    ui_configs = configurations("ui", {
        "PRODUCT_BUNDLE_IDENTIFIER": "$(BROWSER_BUNDLE_ID).uitests", "PRODUCT_NAME": "$(TARGET_NAME)",
        "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "PersonalBrowser",
        "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphonesimulator",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]
    })

    def phases(kind):
        sources = add("sources:" + kind, "PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_ids[kind], runOnlyForDeploymentPostprocessing=0)
        frameworks = add("frameworks:" + kind, "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
        resources = []
        if kind == "app":
            resources.append(add("build:Assets", "PBXBuildFile", fileRef=identifier("file:Assets")))
            resources.append(add("build:FilterResources", "PBXBuildFile", fileRef=identifier("file:FilterResources")))
        resources_phase = add("resources:" + kind, "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)
        return [sources, frameworks, resources_phase]

    app_target = add("target:app", "PBXNativeTarget", buildConfigurationList=app_configs, buildPhases=phases("app"), buildRules=[], dependencies=[], name="PersonalBrowser", productName="PersonalBrowser", productReference=app_product, productType="com.apple.product-type.application")
    proxy = add("proxy:app", "PBXContainerItemProxy", containerPortal=identifier("project"), proxyType=1, remoteGlobalIDString=app_target, remoteInfo="PersonalBrowser")
    dependency = add("dependency:app", "PBXTargetDependency", target=app_target, targetProxy=proxy)
    ui_target = add("target:ui", "PBXNativeTarget", buildConfigurationList=ui_configs, buildPhases=phases("ui"), buildRules=[], dependencies=[dependency], name="PersonalBrowserUITests", productName="PersonalBrowserUITests", productReference=ui_product, productType="com.apple.product-type.bundle.ui-testing")
    add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1640", "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "16.4"}, ui_target: {"CreatedOnToolsVersion": "16.4", "TestTargetID": app_target}}}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="ja", hasScannedForEncodings=0, knownRegions=["ja", "en", "Base"], mainGroup=root_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app_target, ui_target])
    content = "// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": identifier("project")}) + "\n"

    def reference(target, name, extension):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{escape(name)}.{extension}" BlueprintName="{escape(name)}" ReferencedContainer="container:PersonalBrowser.xcodeproj"/>'

    app_ref = reference(app_target, "PersonalBrowser", "app")
    ui_ref = reference(ui_target, "PersonalBrowserUITests", "xctest")
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
      <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{ui_ref}</BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO">{ui_ref}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    return {ROOT / "PersonalBrowser.xcodeproj/project.pbxproj": content,
            ROOT / "PersonalBrowser.xcodeproj/xcshareddata/xcschemes/PersonalBrowser.xcscheme": scheme}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    different = []
    for path, content in generate().items():
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                different.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if different:
        print("Regenerate with python3 scripts/generate_project.py: " + ", ".join(different), file=sys.stderr)
        return 1
    print("Xcode project is current." if args.check else "Generated Xcode project and shared scheme.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
