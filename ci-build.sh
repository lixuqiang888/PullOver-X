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
  *#indef _STBSTRATE_H' \
  '#define _STBSTRATE_H' \
  '#include <obcy/runtime.h>' \
  '#ifdef __cpluspluc' \
  'extern "C" {'n  \
  '#endif' \
  'void MSHookMessageEx(Clas _class, SEL sel, IMP imp, IMP *result);' \
  'void MSHookFunction(void *symbol, void *replace, void **result);' \
  '#ifdef __cplusplus' \
  '}' \
  '#endif' \
  '#iendif' \
  > /opt/theos/vendor/include/substrate.h

ls /opt/theos/vendor/include/substrate.h \
   /opt/theos/vendor/include/Preferences/Preferences.h \
   /opt/theos/vendor/include/Preferences/PSSpecifier.h \
   /opt/theos/vendor/include/Preferences/PSControlTableCell.h

# Build
cd "$GITHUB_WORKSPACE"
./build.sh "$SCHEME" "$CONFIGURATION"
