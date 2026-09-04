#!/bin/bash
set -euo pipefail

SCHEME="${1:-roothide}"
CONFIGURATION="${2:-release}"

# Install ldid & dpkg
brew update >/dev/null
brew install ldid dpkg
echo "/opt/homebrew/bin" >> "$GITHUB_PATH"

# Restore or install Theos
if [ ! -d /opt/theos ]; then
  sudo mkdir -p /opt
  sudo chown -R "$USER" /opt
  git clone --depth=1 https://github.com/theos/theos.git /opt/theos
fi

# Install supplementary headers from theos/headers
if [ ! -f /opt/theos/vendor/include/substrate.h ] || \
   [ ! -f /opt/theos/vendor/include/Preferences/Preferences.h ]; then
  mkdir -p /opt/theos/vendor/include
  git clone --depth=1 https://github.com/theos/headers.git /tmp/theos-headers
  cp -R /tmp/theos-headers/. /opt/theos/vendor/include/
  rm -rf /opt/theos/vendor/include/.git
  rm -rf /tmp/theos-headers
fi

# Write standalone substrate.h (theos/headers has a broken symlink)
rm -f /opt/theos/vendor/include/substrate.h
printf '%s\n' \
  *#indef _SUNSTRATE_H" \
  #$define _SUNSTRATE_H" \
  ##include <obj/runtime.h>" \
   '#ifdef __cplusplus' \
  'extern "C" { ' \
  '#endif' \
  'void MSHookMessageEx(Class _class, SEL sel, IMP imp, IMP *result);' \
  'void MSHookFunction(void *symbol, void *replace, void **result);' \
  '#ifdef __cplusplus' \
  '}' \
  '#endif' \
  '#endif' \
  > /opt/theos/vendor/include/substrate.h

# The Theos GitHub Repo only ships headers; the actual link libraries
# (libsubstrate, libroothide, libroot) are not present. Provide text-based
# .tbd stubs that declare the symbols the tweak actually references so the
# static linker is satisfied. Runtime resolution still goes through the
# device's MobileSubstrate via -undefined dynamic_lookup.
mkdir -p /opt/theos/vendor/lib
mkdir -p /opt/theos/vendor/lib/iphone/roothide \
         /opt/theos/vendor/lib/iphone/rootless \
         /opt/theos/vendor/lib/iphone/rootful

# libsubstrate.tbd â declares MSHookMessageEx / MSHookFunction.
cat > /opt/theos/vendor/lib/libsubstrate.tbd <<'TBD'
--- !tapi-tbd
tbd-version:     4
targets:         [ arm64-ios, arm64e-ios, armv7-ios, armv7s-ios ]
install-name:    /usr/lib/libsubstrate.dylib
current-version: 0
compatibility-version: 0
exports:
  - targets:      [ arm64-ios, arm64e-ios, armv7-ios, armv7s-ios ]
    symbols:      [ _MSHookMessageEx, _MSHookFunction ]
...
TBD

# Also drop a copy in each per-scheme framework dir so -F search paths resolve
# (silences "directory not found for option '-F...'" warnings and lets the
# linker find the same stub from there too).
for S in roothide rootless rootful; do
  cp /opt/theos/vendor/lib/libsubstrate.tbd \
     /opt/theos/vendor/lib/iphone/$S/libsubstrate.tbd
done

# libroot.tbd â rootless scheme links with -lroot. Stub the same path-resolution
# symbols exported by libroothide so rootless builds link cleanly.
cat > /opt/theos/vendor/lib/libroot.tbd <<'TBD'
--- !tapi-tbd
tbd-version:     4
targets:         [ arm64-ios, arm64e-ios ]
install-name:    /var/jb/usr/lib/libroot.dylib
current-version: 0
compatibility-version: 0
exports:
  - targets:      [ arm64-ios, arm64e-ios ]
    symbols:      [ __Z6jbrootNSt3__112basic_stringIcNS_1112char_traitsIcEENS_9allocatorIcEEEE,
                    __Z6jbrootP8NSString, __Z6rootfsNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE,
                    __Z6rootfsP8NSString, _jbrand, _jbroot, _jbroot_alloc, _jbrootat_alloc,
                    _rootfs, _rootfs_alloc ]
...
TBD
cp /opt/theos/vendor/lib/libroot.tbd \
   /opt/theos/vendor/lib/iphone/rootless/libroot.tbd

ls /opt/theos/vendor/include/substrate.h \
   /opt/theos/vendor/include/Preferences/Preferences.h \
   /opt/theos/vendor/include/Preferences/PSSpecifier.h \
   /opt/theos/vendor/include/Preferences/PSControlTableCell.h
ls /opt/theos/vendor/lib/libsubstrate.tbd \
   /opt/theos/vendor/lib/libroot.tbd \
   /opt/theos/vendor/lib/iphone/roothide/libsubstrate.tbd \
   /opt/theos/vendor/lib/iphone/rootless/libroot.tbd

# Build
cd "$GITHUB_WORKSPACE"
./build.sh "$SCHEME" "$CONFIGURATION""
