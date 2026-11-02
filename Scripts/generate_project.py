#!/usr/bin/env python3
"""Generate the MacGuard Xcode project deterministically.

The project is committed so the repository opens without extra tooling. This
script is here for reproducibility after adding or removing source files.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_DIR = ROOT / "MacGuard.xcodeproj"
PROJECT_NAME = "MacGuard"
KIT_NAME = "MacGuardKit"
APP_NAME = "MacGuard"
TEST_NAME = "MacGuardTests"


def uid(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def swift_files(base: Path) -> list[Path]:
    return sorted(path for path in base.rglob("*.swift") if path.is_file())


KIT_FILES = swift_files(ROOT / "Sources" / KIT_NAME)
APP_FILES = swift_files(ROOT / "Sources" / APP_NAME)
TEST_FILES = swift_files(ROOT / "Tests" / TEST_NAME)

KIT_GROUPS = ["Models", "Engine", "Persistence", "Support", "App"]
APP_GROUPS = ["App", "Views", "Resources"]


def group_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def file_type(path: Path) -> str:
    suffixes = path.suffixes
    if path.suffix == ".swift":
        return "sourcecode.swift"
    if path.suffix == ".xcassets":
        return "folder.assetcatalog"
    if path.suffix == ".plist":
        return "text.plist.xml"
    if path.suffix == ".entitlements":
        return "text.plist.entitlements"
    if path.suffix == ".framework":
        return "wrapper.framework"
    if path.suffix == ".app":
        return "wrapper.application"
    if path.suffix == ".xctest":
        return "wrapper.cfbundle"
    return "text"


def esc(value: str) -> str:
    if value == "":
        return '""'
    if value.startswith(("-", "@")):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if all(ch.isalnum() or ch in "_./:-+@$" for ch in value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def serialize(value, indent: int = 0) -> str:
    pad = "\t" * indent
    if isinstance(value, dict):
        if not value:
            return "{}"
        value = {k: v for k, v in value.items() if k != "comment"}
        lines = ["{"]
        for key, item in value.items():
            lines.append(f"{pad}\t{key} = {serialize(item, indent + 1)};")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    if isinstance(value, (list, tuple)):
        if not value:
            return "()"
        lines = ["("]
        for item in value:
            if isinstance(item, dict):
                lines.append(f"{pad}\t{serialize(item, indent + 1)},")
            else:
                lines.append(f"{pad}\t{serialize(item, indent + 1)},")
        lines.append(f"{pad})")
        return "\n".join(lines)
    if isinstance(value, bool):
        return "YES" if value else "NO"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return esc(value)
    raise TypeError(f"Unsupported value: {value!r}")


objects: dict[str, dict] = {}


def add(key: str, obj: dict) -> str:
    obj["comment"] = obj.get("comment", key)
    objects[key] = obj
    return key


# ---------------------------------------------------------------------------
# File references and groups
# ---------------------------------------------------------------------------

def add_file_ref(path: Path) -> str:
    key = f"file:{group_path(path)}"
    if key in objects:
        return key
    name = path.name
    add(key, {
        "isa": "PBXFileReference",
        "lastKnownFileType": file_type(path),
        "name": name,
        "path": name,
        "sourceTree": "<group>",
    })
    return key


def add_group(path: Path, parent: str | None, children: list[str]) -> str:
    key = f"group:{group_path(path)}"
    add(key, {
        "isa": "PBXGroup",
        "children": children,
        "path": path.name,
        "sourceTree": "<group>",
    })
    return key


# Main group
main_group = f"group:main"
products_group = f"group:products"
sources_group = f"group:sources"
tests_group = f"group:tests"

add(main_group, {
    "isa": "PBXGroup",
    "children": [sources_group, tests_group, products_group],
    "sourceTree": "<group>",
})
add(products_group, {
    "isa": "PBXGroup",
    "children": [],
    "name": "Products",
    "sourceTree": "<group>",
})
add(sources_group, {
    "isa": "PBXGroup",
    "children": [],
    "path": "Sources",
    "sourceTree": "<group>",
})
add(tests_group, {
    "isa": "PBXGroup",
    "children": [],
    "path": "Tests",
    "sourceTree": "<group>",
})

# Kit groups
kit_group = f"group:Sources/{KIT_NAME}"
add(kit_group, {
    "isa": "PBXGroup",
    "children": [],
    "path": KIT_NAME,
    "sourceTree": "<group>",
})
objects[sources_group]["children"].append(kit_group)

for group_name in KIT_GROUPS:
    group_dir = ROOT / "Sources" / KIT_NAME / group_name
    children = []
    for file in KIT_FILES:
        if file.parent == group_dir:
            children.append(add_file_ref(file))
    key = add_group(group_dir, kit_group, children)
    objects[kit_group]["children"].append(key)

# App groups
app_group = f"group:Sources/{APP_NAME}"
add(app_group, {
    "isa": "PBXGroup",
    "children": [],
    "path": APP_NAME,
    "sourceTree": "<group>",
})
objects[sources_group]["children"].append(app_group)

for group_name in APP_GROUPS:
    group_dir = ROOT / "Sources" / APP_NAME / group_name
    children = []
    if group_name == "Resources":
        children.append(add_file_ref(group_dir / "Assets.xcassets"))
    for file in APP_FILES:
        if file.parent == group_dir:
            children.append(add_file_ref(file))
    key = add_group(group_dir, app_group, children)
    objects[app_group]["children"].append(key)

info_plist = add_file_ref(ROOT / "Sources" / APP_NAME / "Info.plist")
entitlements = add_file_ref(ROOT / "Sources" / APP_NAME / "MacGuard.entitlements")
objects[app_group]["children"].extend([info_plist, entitlements])

# Test group
test_group = f"group:Tests/{TEST_NAME}"
add(test_group, {
    "isa": "PBXGroup",
    "children": [add_file_ref(file) for file in TEST_FILES],
    "path": TEST_NAME,
    "sourceTree": "<group>",
})
objects[tests_group]["children"].append(test_group)

# Products
kit_product = f"product:{KIT_NAME}.framework"
app_product = f"product:{APP_NAME}.app"
test_product = f"product:{TEST_NAME}.xctest"
add(kit_product, {
    "isa": "PBXFileReference",
    "lastKnownFileType": "wrapper.framework",
    "name": f"{KIT_NAME}.framework",
    "path": f"{KIT_NAME}.framework",
    "sourceTree": "BUILT_PRODUCTS_DIR",
})
add(app_product, {
    "isa": "PBXFileReference",
    "lastKnownFileType": "wrapper.application",
    "name": f"{APP_NAME}.app",
    "path": f"{APP_NAME}.app",
    "sourceTree": "BUILT_PRODUCTS_DIR",
})
add(test_product, {
    "isa": "PBXFileReference",
    "lastKnownFileType": "wrapper.cfbundle",
    "name": f"{TEST_NAME}.xctest",
    "path": f"{TEST_NAME}.xctest",
    "sourceTree": "BUILT_PRODUCTS_DIR",
})
objects[products_group]["children"] = [kit_product, app_product, test_product]

# ---------------------------------------------------------------------------
# Build files
# ---------------------------------------------------------------------------

def build_file(key: str, file_ref: str, comment: str, settings: dict | None = None) -> str:
    obj = {
        "isa": "PBXBuildFile",
        "fileRef": file_ref,
    }
    if settings:
        obj["settings"] = settings
    add(key, obj)
    return key


kit_build_files = [build_file(f"bf:kit:{group_path(file)}", add_file_ref(file), f"{file.name} in Sources") for file in KIT_FILES]
app_build_files = [build_file(f"bf:app:{group_path(file)}", add_file_ref(file), f"{file.name} in Sources") for file in APP_FILES]
test_build_files = [build_file(f"bf:test:{group_path(file)}", add_file_ref(file), f"{file.name} in Sources") for file in TEST_FILES]

assets_build = build_file("bf:app:Assets.xcassets", add_file_ref(ROOT / "Sources" / APP_NAME / "Resources" / "Assets.xcassets"), "Assets.xcassets in Resources")
app_framework_build = build_file("bf:app:framework:MacGuardKit.framework", kit_product, "MacGuardKit.framework in Frameworks")
app_copy_build = build_file("bf:app:copy:MacGuardKit.framework", kit_product, "MacGuardKit.framework in Embed Frameworks")
test_framework_build = build_file("bf:test:framework:MacGuardKit.framework", kit_product, "MacGuardKit.framework in Frameworks")

# ---------------------------------------------------------------------------
# Build phases
# ---------------------------------------------------------------------------

def sources_phase(key: str, comment: str, files: list[str]) -> str:
    add(key, {
        "isa": "PBXSourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": files,
        "runOnlyForDeploymentPostprocessing": 0,
    })
    return key


def frameworks_phase(key: str, files: list[str]) -> str:
    add(key, {
        "isa": "PBXFrameworksBuildPhase",
        "buildActionMask": 2147483647,
        "files": files,
        "runOnlyForDeploymentPostprocessing": 0,
    })
    return key


def resources_phase(key: str, files: list[str]) -> str:
    add(key, {
        "isa": "PBXResourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": files,
        "runOnlyForDeploymentPostprocessing": 0,
    })
    return key


kit_sources = sources_phase("phase:kit:sources", "Sources", kit_build_files)
kit_frameworks = frameworks_phase("phase:kit:frameworks", [])
kit_resources = resources_phase("phase:kit:resources", [])

app_sources = sources_phase("phase:app:sources", "Sources", app_build_files)
app_frameworks = frameworks_phase("phase:app:frameworks", [app_framework_build])
app_resources = resources_phase("phase:app:resources", [assets_build])
add("phase:app:copy", {
    "isa": "PBXCopyFilesBuildPhase",
    "buildActionMask": 2147483647,
    "dstPath": "$(CONTENTS_FOLDER_PATH)/Frameworks",
    "dstSubfolderSpec": 10,
    "files": [app_copy_build],
    "runOnlyForDeploymentPostprocessing": 0,
})

test_sources = sources_phase("phase:test:sources", "Sources", test_build_files)
test_frameworks = frameworks_phase("phase:test:frameworks", [test_framework_build])
test_resources = resources_phase("phase:test:resources", [])

# ---------------------------------------------------------------------------
# Targets, dependencies, configurations
# ---------------------------------------------------------------------------

kit_target = "target:MacGuardKit"
app_target = "target:MacGuard"
test_target = "target:MacGuardTests"

app_dep = "dep:app:MacGuardKit"
test_dep = "test:dep:MacGuardKit"
app_proxy = "proxy:app:MacGuardKit"
test_proxy = "proxy:test:MacGuardKit"

add(app_dep, {
    "isa": "PBXTargetDependency",
    "target": kit_target,
    "targetProxy": app_proxy,
})
add(test_dep, {
    "isa": "PBXTargetDependency",
    "target": kit_target,
    "targetProxy": test_proxy,
})
add(app_proxy, {
    "isa": "PBXContainerItemProxy",
    "containerPortal": "root",
    "proxyType": 1,
    "remoteGlobalIDString": kit_target,
    "remoteInfo": KIT_NAME,
})
add(test_proxy, {
    "isa": "PBXContainerItemProxy",
    "containerPortal": "root",
    "proxyType": 1,
    "remoteGlobalIDString": kit_target,
    "remoteInfo": KIT_NAME,
})

project_settings = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_MODULE_DEBUGGABLE": "YES",
    "CLANG_ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_DIRECTIVE": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_NS_IMPLICIT_BOOLEAN_CONVERSION": "YES",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEAD_CODE_STRIPPING": "YES",
    "ENABLE_STRICT_PROTOTYPES": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0",
    "SWIFT_STRICT_CONCURRENCY": "minimal",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "VERSIONING_SYSTEM": "apple-generic",
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "1.0.0",
}

debug_settings = dict(project_settings)
debug_settings.update({
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ("DEBUG=1", "$(inherited)"),
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    "SWIFT_COMPILATION_MODE": "singlefile",
})

release_settings = dict(project_settings)
release_settings.update({
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "s",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "ONLY_ACTIVE_ARCH": "NO",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "DEPLOYMENT_POSTPROCESSING": "YES",
    "STRIP_INSTALLED_PRODUCT": "YES",
    "STRIP_STYLE": "non-global",
})


def config(key: str, name: str, settings: dict) -> str:
    add(key, {
        "isa": "XCBuildConfiguration",
        "buildSettings": settings,
        "name": name,
    })
    return key


def config_list(key: str, debug: str, release: str) -> str:
    add(key, {
        "isa": "XCConfigurationList",
        "buildConfigurations": [debug, release],
        "defaultConfigurationIsVisible": 0,
        "defaultConfigurationName": "Release",
    })
    return key


project_debug = config("config:project:Debug", "Debug", debug_settings)
project_release = config("config:project:Release", "Release", release_settings)
project_config_list = config_list("configlist:project", project_debug, project_release)

kit_debug = dict(debug_settings)
kit_debug.update({
    "DEFINES_MODULE": "YES",
    "DYLIB_COMPATIBILITY_VERSION": "1",
    "DYLIB_CURRENT_VERSION": "1",
    "DYLIB_INSTALL_NAME_BASE": "@rpath",
    "FRAMEWORK_VERSION": "A",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.macguard.kit",
    "PRODUCT_BUNDLE_PACKAGE_TYPE": "FMWK",
    "PRODUCT_NAME": KIT_NAME,
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
})
kit_release = dict(release_settings)
kit_release.update(kit_debug)
kit_debug_config = config("config:kit:Debug", "Debug", kit_debug)
kit_release_config = config("config:kit:Release", "Release", kit_release)
kit_config_list = config_list("configlist:kit", kit_debug_config, kit_release_config)

app_debug = dict(debug_settings)
app_debug.update({
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS": "YES",
    "CODE_SIGN_ENTITLEMENTS": "Sources/MacGuard/MacGuard.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "COMBINE_HIDPI_IMAGES": "YES",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "FRAMEWORK_SEARCH_PATHS": "$(inherited) $(BUILT_PRODUCTS_DIR)",
    "INFOPLIST_FILE": "Sources/MacGuard/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.macguard.app",
    "PRODUCT_MODULE_NAME": APP_NAME,
    "PRODUCT_NAME": APP_NAME,
    "SWIFT_EMIT_LOC_STRINGS": "YES",
})
app_release = dict(release_settings)
app_release.update(app_debug)
app_debug_config = config("config:app:Debug", "Debug", app_debug)
app_release_config = config("config:app:Release", "Release", app_release)
app_config_list = config_list("configlist:app", app_debug_config, app_release_config)

test_debug = dict(debug_settings)
test_debug.update({
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "FRAMEWORK_SEARCH_PATHS": "$(inherited) $(BUILT_PRODUCTS_DIR)",
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.macguard.tests",
    "PRODUCT_BUNDLE_PACKAGE_TYPE": "BNDL",
    "PRODUCT_NAME": TEST_NAME,
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/MacGuard.app/Contents/MacOS/MacGuard",
})
test_release = dict(release_settings)
test_release.update(test_debug)
test_debug_config = config("config:test:Debug", "Debug", test_debug)
test_release_config = config("config:test:Release", "Release", test_release)
test_config_list = config_list("configlist:test", test_debug_config, test_release_config)

add(kit_target, {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": kit_config_list,
    "buildPhases": [kit_sources, kit_frameworks, kit_resources],
    "buildRules": [],
    "dependencies": [],
    "name": KIT_NAME,
    "productName": KIT_NAME,
    "productReference": kit_product,
    "productType": "com.apple.product-type.framework",
})
add(app_target, {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": app_config_list,
    "buildPhases": [app_sources, app_frameworks, app_resources, "phase:app:copy"],
    "buildRules": [],
    "dependencies": [app_dep],
    "name": APP_NAME,
    "productName": APP_NAME,
    "productReference": app_product,
    "productType": "com.apple.product-type.application",
})
add(test_target, {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": test_config_list,
    "buildPhases": [test_sources, test_frameworks, test_resources],
    "buildRules": [],
    "dependencies": [test_dep],
    "name": TEST_NAME,
    "productName": TEST_NAME,
    "productReference": test_product,
    "productType": "com.apple.product-type.bundle.unit-test",
})

# ---------------------------------------------------------------------------
# Project object
# ---------------------------------------------------------------------------

root_key = "root"
add(root_key, {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": "YES",
        "LastSwiftUpdateCheck": "1600",
        "LastUpgradeCheck": "1600",
        "TargetAttributes": {
            kit_target: {"CreatedOnToolsVersion": "16.0"},
            app_target: {"CreatedOnToolsVersion": "16.0"},
            test_target: {"CreatedOnToolsVersion": "16.0"},
        },
    },
    "buildConfigurationList": project_config_list,
    "compatibilityVersion": "Xcode 15.0",
    "developmentRegion": "en",
    "hasScannedForEncodings": "0",
    "knownRegions": ("en", "Base"),
    "mainGroup": main_group,
    "productRefGroup": products_group,
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [kit_target, app_target, test_target],
})

# ---------------------------------------------------------------------------
# Serialize
# ---------------------------------------------------------------------------

uuid_map = {key: uid(key) for key in objects}
if len(set(uuid_map.values())) != len(uuid_map):
    raise RuntimeError("UUID collision detected")


def resolve(value):
    if isinstance(value, str):
        return uuid_map.get(value, value)
    if isinstance(value, (list, tuple)):
        return [resolve(item) for item in value]
    if isinstance(value, dict):
        return {resolve(key): resolve(item) for key, item in value.items()}
    return value


PROJECT_DIR.mkdir(parents=True, exist_ok=True)
pbxproj = PROJECT_DIR / "project.pbxproj"
header = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n"
body = "\n".join(f"\t\t{uuid_map[key]} /* {objects[key].get('comment', key)} */ = {serialize(resolve(obj), 2)};" for key, obj in objects.items())
footer = f"\n\t}};\n\trootObject = {uuid_map[root_key]} /* Project object */;\n}}\n"
pbxproj.write_text(header + body + footer, encoding="utf-8")

# Shared scheme
scheme_dir = PROJECT_DIR / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{uid(app_target)}"
               BuildableName = "MacGuard.app"
               BlueprintName = "MacGuard"
               ReferencedContainer = "container:MacGuard.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{uid(test_target)}"
               BuildableName = "MacGuardTests.xctest"
               BlueprintName = "MacGuardTests"
               ReferencedContainer = "container:MacGuard.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "XcodeDebuggerFoundation.IDERunDestination"
      selectedLauncherIdentifier = "Xcode.IDERunDestination"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{uid(test_target)}"
               BuildableName = "MacGuardTests.xctest"
               BlueprintName = "MacGuardTests"
               ReferencedContainer = "container:MacGuard.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "XcodeDebuggerFoundation.IDERunDestination"
      selectedLauncherIdentifier = "Xcode.IDERunDestination"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{uid(app_target)}"
            BuildableName = "MacGuard.app"
            BlueprintName = "MacGuard"
            ReferencedContainer = "container:MacGuard.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{uid(app_target)}"
            BuildableName = "MacGuard.app"
            BlueprintName = "MacGuard"
            ReferencedContainer = "container:MacGuard.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
(scheme_dir / "MacGuard.xcscheme").write_text(scheme, encoding="utf-8")

print(f"Generated {pbxproj}")
print(f"Kit files: {len(KIT_FILES)}, app files: {len(APP_FILES)}, test files: {len(TEST_FILES)}")
