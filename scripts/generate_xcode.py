"""Generate a dependency-free, shared Xcode project on Windows or macOS."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1] / 'ios'
PROJECT = ROOT / 'FRAME.xcodeproj'
objects = {}

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)

def add(name, content):
    identifier = uid(name)
    objects[identifier] = content
    return identifier

def listing(values):
    return '(' + ', '.join(values) + (',' if values else '') + ')'

app = uid('app-target')
tests = uid('tests-target')
project = uid('project')
app_product = add('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = FRAME.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = FRAMETests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
config = add('config-file', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config.xcconfig; sourceTree = "<group>";')

def file_group(folder):
    references, source_builds, resource_builds = [], [], []
    for file in sorted((ROOT / folder).rglob('*')):
        if not file.is_file() or '.xcassets' in str(file) or file.suffix not in ('.swift', '.xcprivacy'):
            continue
        relative = file.relative_to(ROOT).as_posix()
        kind = 'sourcecode.swift' if file.suffix == '.swift' else 'text.xml'
        ref = add('ref:' + relative, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(relative)}; sourceTree = SOURCE_ROOT;')
        build = add('build:' + relative, f'isa = PBXBuildFile; fileRef = {ref};')
        references.append(ref)
        (source_builds if file.suffix == '.swift' else resource_builds).append(build)
    if folder == 'FRAME':
        ref = add('assets-ref', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = FRAME/Assets.xcassets; sourceTree = SOURCE_ROOT;')
        references.append(ref)
        resource_builds.append(add('assets-build', f'isa = PBXBuildFile; fileRef = {ref};'))
    group = add('group:' + folder, f'isa = PBXGroup; children = {listing(references)}; name = {quoted(folder)}; sourceTree = "<group>";')
    sources = add('sources:' + folder, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {listing(source_builds)}; runOnlyForDeploymentPostprocessing = 0;')
    resources = add('resources:' + folder, f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {listing(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = add('frameworks:' + folder, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    return group, [sources, frameworks, resources]

app_group, app_phases = file_group('FRAME')
test_group, test_phases = file_group('FRAMETests')
products_group = add('products-group', f'isa = PBXGroup; children = {listing([app_product, test_product])}; name = Products; sourceTree = "<group>";')
main_group = add('main-group', f'isa = PBXGroup; children = {listing([app_group, test_group, config, products_group])}; sourceTree = "<group>";')

def configurations(name, settings, base=None):
    configs = []
    for mode in ('Debug', 'Release'):
        merged = dict(settings)
        merged['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if mode == 'Debug' else '-O'
        if mode == 'Debug':
            merged['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        values = ' '.join(f'{key} = {quoted(value)};' for key, value in merged.items())
        configs.append(add(f'{name}:{mode}', f'isa = XCBuildConfiguration; ' + (f'baseConfigurationReference = {base}; ' if base else '') + f'buildSettings = {{ {values} }}; name = {mode};'))
    return add(name + ':config-list', f'isa = XCConfigurationList; buildConfigurations = {listing(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_config = configurations('project', {
    'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0',
    'CLANG_ENABLE_MODULES': 'YES', 'CODE_SIGN_STYLE': 'Automatic', 'ENABLE_TESTABILITY': 'YES',
    'TARGETED_DEVICE_FAMILY': '1,2', 'MARKETING_VERSION': '1.0.0', 'CURRENT_PROJECT_VERSION': '1',
    'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SWIFT_EMIT_LOC_STRINGS': 'YES',
    'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_KEY_CFBundleDisplayName': 'FRAME',
    'INFOPLIST_KEY_LSApplicationCategoryType': 'public.app-category.entertainment',
    'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption': 'NO',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations': 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'INFOPLIST_KEY_FRAMEAPIHost': '$(FRAME_API_HOST)',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
}, config)
app_config = configurations('app', {'PRODUCT_NAME': '$(TARGET_NAME)', 'CODE_SIGN_ENTITLEMENTS': 'FRAME/FRAME.entitlements'})
test_config = configurations('tests', {
    'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.rymlk.frame.tests',
    'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/FRAME.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/FRAME',
    'BUNDLE_LOADER': '$(TEST_HOST)', 'ASSETCATALOG_COMPILER_APPICON_NAME': '',
})
proxy = add('target-proxy', f'isa = PBXContainerItemProxy; containerPortal = {project}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = FRAME;')
dependency = add('test-dependency', f'isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};')
add('app-target', f'isa = PBXNativeTarget; buildConfigurationList = {app_config}; buildPhases = {listing(app_phases)}; buildRules = (); dependencies = (); name = FRAME; productName = FRAME; productReference = {app_product}; productType = "com.apple.product-type.application";')
add('tests-target', f'isa = PBXNativeTarget; buildConfigurationList = {test_config}; buildPhases = {listing(test_phases)}; buildRules = (); dependencies = ({dependency},); name = FRAMETests; productName = FRAMETests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{ {tests} = {{ TestTargetID = {app}; }}; }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr, en, Base); mainGroup = {main_group}; productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = ({app}, {tests},);')
PROJECT.mkdir(parents=True, exist_ok=True)
content = '// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'
content += ''.join(f'  {key} = {{ {value} }};\n' for key, value in sorted(objects.items()))
content += f' }};\n rootObject = {project};\n}}\n'
(PROJECT / 'project.pbxproj').write_text(content, encoding='utf-8')
scheme_dir = PROJECT / 'xcshareddata' / 'xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
scheme_dir.joinpath('FRAME.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="FRAME.app" BlueprintName="FRAME" ReferencedContainer="container:FRAME.xcodeproj"/></BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tests}" BuildableName="FRAMETests.xctest" BlueprintName="FRAMETests" ReferencedContainer="container:FRAME.xcodeproj"/></TestableReference>
</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="FRAME.app" BlueprintName="FRAME" ReferencedContainer="container:FRAME.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''', encoding='utf-8')
print('Generated ios/FRAME.xcodeproj and shared FRAME scheme')
