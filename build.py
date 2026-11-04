#!/usr/bin/env python3
"""Build the native ARM64 development app and DMG. No Windows runtime."""
from pathlib import Path
import subprocess, tempfile, shutil, plistlib, os, hashlib, json
base=Path(__file__).resolve().parent
stage=Path(tempfile.mkdtemp(prefix='tc-native-'))
app=stage/'Total Commander Native.app'
res=app/'Contents/Resources';res.mkdir(parents=True)
binary=app/'Contents/MacOS/NativeCommander';binary.parent.mkdir()
def run(*args): subprocess.run([str(x) for x in args],check=True)
source_hashes={str(p.relative_to(base)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((base/'Sources').glob('*.swift'))}
run('xcrun','swiftc','-swift-version','5','-O','-target','arm64-apple-macosx13.0','-framework','AppKit','-framework','ImageIO',*sorted((base/'Sources').glob('*.swift')),'-o',binary)
assert source_hashes=={str(p.relative_to(base)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((base/'Sources').glob('*.swift'))}, 'Sources changed during compilation; rebuild required'
(res/'build-manifest.json').write_text(json.dumps(source_hashes,indent=2)+'\n')
shutil.copy2(base/'Resources/7zz',res/'7zz')
for name in ['WCMD_ENG.MNU','TOTALCMD.INC']:
 shutil.copy2(base/'Resources'/name,res/name)
shutil.copytree(base/'Resources/licenses',res/'licenses')
shutil.copytree(base/'Resources/icons',res/'icons')
shutil.copy2(base/'Resources/TotalCommander.icns',res/'TotalCommander.icns')
for name in ['README.md','TEST-RESULTS.md','THIRD-PARTY.txt','LICENSE']:
 if (base/name).exists(): shutil.copy2(base/name,res/name)
shutil.copytree(base/'analysis',res/'analysis')
if (base/'docs').exists():
 shutil.copytree(base/'docs',res/'docs')
 shutil.copytree(base/'docs',stage/'docs')
info=dict(CFBundleName='Total Commander Native',CFBundleIconFile='TotalCommander',CFBundleDisplayName='Total Commander Native',CFBundleIdentifier='local.totalcommander.native',CFBundleExecutable='NativeCommander',CFBundlePackageType='APPL',CFBundleShortVersionString='0.8.0',CFBundleVersion='9',LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True,NSPrincipalClass='NSApplication')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
run('codesign','--force','--sign','-',res/'7zz')
run('codesign','--force','--deep','--sign','-',app)
run('codesign','--verify','--deep','--strict',app)
if (base/'README.md').exists(): shutil.copy2(base/'README.md',stage/'README.md')
(stage/'Applications').symlink_to('/Applications')
dmg=base/'Total-Commander-Native-development.dmg'
run('hdiutil','create','-volname','Total Commander Native','-srcfolder',stage,'-ov','-format','UDZO',dmg)
(base/'build-stage.txt').write_text(str(stage)+'\n')
print('Native app:',app)
print('DMG:',dmg)
