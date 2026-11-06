#!/bin/bash
# Put the shared libgcc ahead of the static one so emutls comes from libgcc_s_seh-1.dll.
args=()
for a in "$@"; do
  [ "$a" = "-lgcc_eh" ] && args+=("-lgcc_s")
  args+=("$a")
done
exec x86_64-w64-mingw32-g++-posix "${args[@]}"
