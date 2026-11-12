"""Generate SDK-owned Android/iOS tooling while preserving native wallet code."""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import plistlib

ROOT = Path(__file__).resolve().parent.parent


def main():
    flutter = shutil.which('flutter')
    if not flutter:
        sys.exit('Install the latest stable Flutter SDK and add flutter/bin to PATH first.')
    stage = ROOT / '.dart_tool' / 'platform_scaffold'
    if stage.exists():
        sys.exit(f'Scaffold already exists: {stage}. Rename that directory before retrying.')
    overrides = {}
    for platform in ('android', 'ios'):
        for file in (ROOT / platform).rglob('*'):
            if file.is_file() and file.suffix in ('.xml', '.kt', '.swift', '.entitlements'):
                overrides[file.relative_to(ROOT)] = file.read_bytes()
    stage.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([flutter, 'create', '--no-pub', '--platforms=android,ios',
                    '--org', 'com.tapcpeso', '--project-name', 'tapc_peso', str(stage)],
                   cwd=ROOT, check=True)
    for platform in ('android', 'ios'):
        shutil.copytree(stage / platform, ROOT / platform, dirs_exist_ok=True)
    if (stage / '.metadata').exists():
        shutil.copy2(stage / '.metadata', ROOT / '.metadata')
    for relative, data in overrides.items():
        target = ROOT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    gradle = ROOT / 'android/app/build.gradle.kts'
    text = gradle.read_text(encoding='utf-8').replace(
        'minSdk = flutter.minSdkVersion', 'minSdk = maxOf(24, flutter.minSdkVersion)')
    gradle.write_text(text, encoding='utf-8')
    properties = ROOT / 'android/gradle.properties'
    with properties.open('a', encoding='utf-8') as handle:
        handle.write('\ndev.steenbakker.mobile_scanner.useUnbundled=false\n')
    info = ROOT / 'ios/Runner/Info.plist'
    with info.open('rb') as handle:
        plist = plistlib.load(handle)
    plist.update({
        'CFBundleDisplayName': 'TapCPeso',
        'NSCameraUsageDescription': 'Scan offline wallet payment QR codes.',
        'NSFaceIDUsageDescription': 'Authorize offline wallet payments.',
        'NFCReaderUsageDescription': 'Receive offline TapCPeso payments from an Android sender.',
        'com.apple.developer.nfc.readersession.iso7816.select-identifiers':
            ['F0544150435045534F01'],
    })
    with info.open('wb') as handle:
        plistlib.dump(plist, handle, sort_keys=False)
    xcode = ROOT / 'ios/Runner.xcodeproj/project.pbxproj'
    text = xcode.read_text(encoding='utf-8').replace('INFOPLIST_FILE = Runner/Info.plist;',
        'INFOPLIST_FILE = Runner/Info.plist;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;')
    # Respect newer generated deployment targets, raising older ones to iOS 13.
    text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);',
        lambda match: 'IPHONEOS_DEPLOYMENT_TARGET = ' +
        (match[1] if float(match[1]) >= 13 else '13.0') + ';', text)
    xcode.write_text(text, encoding='utf-8')
    subprocess.run([flutter, 'pub', 'get'], cwd=ROOT, check=True)
    print('Native Android and iOS setup ready. Run flutter analyze, flutter test, then flutter run.')
    print('For iOS NFC, enable NFC Tag Reading and configure signing in Xcode on a Mac.')


if __name__ == '__main__':
    main()
