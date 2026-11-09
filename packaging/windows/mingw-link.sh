#!/bin/bash
# Put the shared libgcc ahead of the static one so emutls comes from libgcc_s_seh-1.dll.
args=()
for a in "$@"; do
  [ "$a" = "-lgcc_eh" ] && args+=("-lgcc_s")
  args+=("$a")
done
# The Cypher microphone (cpp/cypher/mic.cpp) sits in a static archive linked
# after -lQt6Multimedia; repeat the library at the end so ld resolves it.
exec x86_64-w64-mingw32-g++-posix "${args[@]}" -lQt6Multimedia
