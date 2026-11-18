import hashlib, json, plistlib, sys, zipfile
from pathlib import Path

ipa = Path(sys.argv[1])
expected = dict(CFBundleVersion=sys.argv[2], CFBundleIdentifier='io.github.wallflow.ios',
                CFBundleDisplayName='映壁', CFBundleExecutable='WallFlow', MinimumOSVersion='26.0',
                DTSDKName='iphoneos27.1', DTSDKBuild='24A94232', DTXcode='2710', DTXcodeBuild='27A9275')
with zipfile.ZipFile(ipa) as z:
    base = 'Payload/WallFlow.app/'
    if z.testzip() or z.getinfo(base + 'WallFlow').file_size == 0:
        sys.exit('Damaged IPA or missing executable')
    info = plistlib.loads(z.read(base + 'Info.plist'))
    for k, v in expected.items():
        if info.get(k) != v:
            sys.exit(f'{k}: expected {v!r}, got {info.get(k)!r}')
print(json.dumps(dict(expected, bytes=ipa.stat().st_size, sha256=hashlib.sha256(ipa.read_bytes()).hexdigest()), ensure_ascii=False, indent=2))
