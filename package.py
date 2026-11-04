#!/usr/bin/env python3
"""Package a matching compiled stage, verify its signature/image, archive committed source."""
from pathlib import Path
import hashlib, json, shutil, subprocess
base=Path(__file__).resolve().parent
stage=Path((base/'build-stage.txt').read_text().strip())
app=stage/'Total Commander Native.app'
res=app/'Contents/Resources'
actual={str(p.relative_to(base)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((base/'Sources').glob('*.swift'))}
if json.loads((res/'build-manifest.json').read_text()) != actual:
    raise SystemExit('Sources differ from the compiled stage. Run build.py first.')
def run(*args): subprocess.run([str(a) for a in args],cwd=base,check=True)
for name in ['README.md','TEST-RESULTS.md','THIRD-PARTY.txt','LICENSE']:
    shutil.copy2(base/name,res/name)
shutil.copytree(base/'analysis',res/'analysis',dirs_exist_ok=True)
if (base/'docs').exists():
    shutil.copytree(base/'docs',res/'docs',dirs_exist_ok=True)
    shutil.copytree(base/'docs',stage/'docs',dirs_exist_ok=True)
shutil.copy2(base/'README.md',stage/'README.md')
run('codesign','--force','--deep','--sign','-',app)
run('codesign','--verify','--deep','--strict',app)
dmg=base/'Total-Commander-Native-development.dmg'
run('hdiutil','create','-volname','Total Commander Native','-srcfolder',stage,'-ov','-format','UDZO',dmg)
run('hdiutil','verify',dmg)
if subprocess.check_output(['git','status','--porcelain','--untracked-files=normal'],cwd=base).strip():
    raise SystemExit('Commit all source/documentation changes before creating the source release archive.')
source=base/'Total-Commander-Native-source.zip'
run('git','archive','--format=zip','--prefix=TotalCommanderNative/','--output',source,'HEAD')
(base/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in [dmg,source]))
print('Packaged',dmg)
