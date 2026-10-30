#!/bin/sh
# Runs swift test against the Command Line Tools' Swift Testing (no Xcode needed).
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
exec swift test \
  -Xswiftc -F"$F" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" "$@"
