#!/usr/bin/env python3
"""Install link-time declarations only; never package a substitute libSandy."""
import os
from pathlib import Path

theos = Path(os.environ['THEOS'])
scheme = os.environ.get('THEOS_PACKAGE_SCHEME', 'roothide')
if scheme == 'roothide':
    install_name = '@loader_path/.jbroot/usr/lib/libsandy.dylib'
    libdirs = [theos / 'vendor/lib', theos / 'lib', theos / 'lib/iphone/rootless']
else:
    install_name = '@rpath/libsandy.dylib'
    libdirs = [theos / 'vendor/lib', theos / 'lib/iphone/rootless', theos / 'lib']
for libdir in libdirs:
    libdir.mkdir(parents=True, exist_ok=True)
    tbd = '''--- !tapi-tbd-v3
archs: [ arm64, arm64e ]
platform: ios
install-name: '%s'
exports:
  - archs: [ arm64, arm64e ]
    symbols: [ _libSandy_applyProfile, _libSandy_works ]
...
''' % install_name
    (libdir / 'libsandy.tbd').write_text(tbd)
    (libdir / 'libSandy.tbd').write_text(tbd)
(theos / 'include/libSandy.h').write_text('''#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
#define kLibSandySuccess 0
#define kLibSandyErrorXPCFailure 1
#define kLibSandyErrorRestricted 2
extern int libSandy_applyProfile(const char *profileName);
extern bool libSandy_works(void);
#ifdef __cplusplus
}
#endif
''')
print('Installed libSandy link interface:', install_name)
