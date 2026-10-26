#!/usr/bin/env python3
"""regenerate StormWatchNJ.xcodeproj/project.pbxproj from the files on disk"""

import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = "StormWatchNJ"
BUNDLE_ID = "com.stormwatchnj.StormWatchNJ"
DEPLOYMENT_TARGET = "17.0"
SOURCE_GROUPS = ["Models", "Services", "Views"]


def oid(*parts):
    digest = hashlib.md5("::".join(parts).encode()).hexdigest().upper()
    return digest[:24]


def collect():
    """returns (root_swift_files, {group: [swift files]})"""
    app_dir = os.path.join(ROOT, APP)
    root_files = sorted(
        f for f in os.listdir(app_dir)
        if f.endswith(".swift") and os.path.isfile(os.path.join(app_dir, f))
    )
    groups = {}
    for group in SOURCE_GROUPS:
        group_dir = os.path.join(app_dir, group)
        if not os.path.isdir(group_dir):
            continue
        groups[group] = sorted(f for f in os.listdir(group_dir) if f.endswith(".swift"))
    return root_files, groups


def main():
    root_files, groups = collect()

    # every compiled source
    sources = [(f, f) for f in root_files]
    for group, files in groups.items():
        sources.extend((f, "%s/%s" % (group, f)) for f in files)

    build_files, file_refs, sources_phase = [], [], []
    for name, relpath in sources:
        ref = oid("fileref", relpath)
        build = oid("buildfile", relpath)
        file_refs.append(
            "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };"
            % (ref, name, name)
        )
        build_files.append(
            "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
            % (build, name, ref, name)
        )
        sources_phase.append("\t\t\t\t%s /* %s in Sources */," % (build, name))

    assets_ref = oid("fileref", "Assets.xcassets")
    assets_build = oid("buildfile", "Assets.xcassets")
    plist_ref = oid("fileref", "Info.plist")
    product_ref = oid("product", APP)

    file_refs.append(
        "\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };"
        % assets_ref
    )
    file_refs.append(
        "\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };"
        % plist_ref
    )
    file_refs.append(
        "\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };"
        % (product_ref, APP, APP)
    )
    build_files.append(
        "\t\t%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };"
        % (assets_build, assets_ref)
    )

    # groups
    group_blocks = []
    app_children = []
    for name in root_files:
        app_children.append("\t\t\t\t%s /* %s */," % (oid("fileref", name), name))
    for group in SOURCE_GROUPS:
        if group not in groups:
            continue
        gid = oid("group", group)
        app_children.append("\t\t\t\t%s /* %s */," % (gid, group))
        children = "\n".join(
            "\t\t\t\t%s /* %s */," % (oid("fileref", "%s/%s" % (group, f)), f)
            for f in groups[group]
        )
        group_blocks.append(
            "\t\t%s /* %s */ = {\n"
            "\t\t\tisa = PBXGroup;\n"
            "\t\t\tchildren = (\n%s\n\t\t\t);\n"
            "\t\t\tpath = %s;\n"
            "\t\t\tsourceTree = \"<group>\";\n"
            "\t\t};" % (gid, group, children, group)
        )
    app_children.append("\t\t\t\t%s /* Assets.xcassets */," % assets_ref)
    app_children.append("\t\t\t\t%s /* Info.plist */," % plist_ref)

    main_group = oid("group", "main")
    app_group = oid("group", "app")
    products_group = oid("group", "products")

    group_blocks.insert(
        0,
        "\t\t%s /* %s */ = {\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n%s\n\t\t\t);\n"
        "\t\t\tpath = %s;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};" % (app_group, APP, "\n".join(app_children), APP),
    )
    group_blocks.insert(
        0,
        "\t\t%s = {\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n\t\t\t\t%s /* %s */,\n\t\t\t\t%s /* Products */,\n\t\t\t);\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};" % (main_group, app_group, APP, products_group),
    )
    group_blocks.append(
        "\t\t%s /* Products */ = {\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n\t\t\t\t%s /* %s.app */,\n\t\t\t);\n"
        "\t\t\tname = Products;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};" % (products_group, product_ref, APP)
    )

    ids = {
        "project": oid("project"),
        "target": oid("target"),
        "sources": oid("phase", "sources"),
        "frameworks": oid("phase", "frameworks"),
        "resources": oid("phase", "resources"),
        "project_list": oid("configlist", "project"),
        "target_list": oid("configlist", "target"),
        "proj_debug": oid("config", "project", "Debug"),
        "proj_release": oid("config", "project", "Release"),
        "tgt_debug": oid("config", "target", "Debug"),
        "tgt_release": oid("config", "target", "Release"),
    }

    project_common = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = %s;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 5.0;""" % DEPLOYMENT_TARGET

    target_common = """\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = %s/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = %s;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";""" % (APP, BUNDLE_ID)

    text = """// !$*UTF8*$!
{
\tarchiveVersion = 1;
\tclasses = {
\t};
\tobjectVersion = 56;
\tobjects = {

/* Begin PBXBuildFile section */
%(build_files)s
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
%(file_refs)s
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t%(frameworks)s /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
%(groups)s
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t%(target)s /* %(app)s */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = %(target_list)s /* Build configuration list for PBXNativeTarget "%(app)s" */;
\t\t\tbuildPhases = (
\t\t\t\t%(sources)s /* Sources */,
\t\t\t\t%(frameworks)s /* Frameworks */,
\t\t\t\t%(resources)s /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = %(app)s;
\t\t\tproductName = %(app)s;
\t\t\tproductReference = %(product)s /* %(app)s.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t%(project)s /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tattributes = {
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {
\t\t\t\t\t%(target)s = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t\tbuildConfigurationList = %(project_list)s /* Build configuration list for PBXProject "%(app)s" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = %(main_group)s;
\t\t\tproductRefGroup = %(products_group)s /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t%(target)s /* %(app)s */,
\t\t\t);
\t\t};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t%(resources)s /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t%(assets_build)s /* Assets.xcassets in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t%(sources)s /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
%(sources_phase)s
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t%(proj_debug)s /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%(project_common)s
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t%(proj_release)s /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%(project_common)s
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\t%(tgt_debug)s /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%(target_common)s
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t%(tgt_release)s /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%(target_common)s
\t\t\t};
\t\t\tname = Release;
\t\t};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t%(project_list)s /* Build configuration list for PBXProject "%(app)s" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t%(proj_debug)s /* Debug */,
\t\t\t\t%(proj_release)s /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\t%(target_list)s /* Build configuration list for PBXNativeTarget "%(app)s" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t%(tgt_debug)s /* Debug */,
\t\t\t\t%(tgt_release)s /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
/* End XCConfigurationList section */
\t};
\trootObject = %(project)s /* Project object */;
}
""" % {
        "build_files": "\n".join(build_files),
        "file_refs": "\n".join(file_refs),
        "groups": "\n".join(group_blocks),
        "sources_phase": "\n".join(sources_phase),
        "app": APP,
        "product": product_ref,
        "assets_build": assets_build,
        "main_group": main_group,
        "products_group": products_group,
        "project_common": project_common,
        "target_common": target_common,
        **ids,
    }

    out_dir = os.path.join(ROOT, "%s.xcodeproj" % APP)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "project.pbxproj"), "w") as handle:
        handle.write(text)
    print("Wrote %s/project.pbxproj (%d Swift files)" % (out_dir, len(sources)))


if __name__ == "__main__":
    main()
