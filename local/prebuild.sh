#!/usr/bin/env sh
set -e

TARGET=./inst/Lua/luajr.lua
NOTICE='-- AUTOGEN: do not edit; assembled by local/prebuild.sh from local/luajr/*.lua'
HASH_PREFIX='-- AUTOGEN-HASH: '

if command -v shasum >/dev/null 2>&1; then
    sha256_stdin() { shasum -a 256 | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
    sha256_stdin() { sha256sum | awk '{print $1}'; }
else
    echo "prebuild.sh: need shasum or sha256sum on PATH" >&2; exit 1
fi

# Guard against direct edits to the generated file. The first two lines hold
# the AUTOGEN notice and a hash of the constituent assembly; stripping them
# should yield exactly cat ./local/luajr/*.lua from when the file was written.
if [ -f "$TARGET" ] && head -2 "$TARGET" | grep -q "^$HASH_PREFIX"; then
    embedded=$(head -2 "$TARGET" | grep "^$HASH_PREFIX" | sed "s|^$HASH_PREFIX||")
    actual=$(sed '1,2d' "$TARGET" | sha256_stdin)
    if [ "$embedded" != "$actual" ] && [ -z "${FORCE:-}" ]; then
        echo "ERROR: $TARGET has been edited directly since the last prebuild." >&2
        echo "  That file is generated; move your changes into the matching" >&2
        echo "  local/luajr/*.lua source file and rerun. FORCE=1 to override." >&2
        exit 1
    fi
fi

echo "Building $TARGET"
new_hash=$(cat ./local/luajr/*.lua | sha256_stdin)
{
    echo "$NOTICE"
    echo "${HASH_PREFIX}${new_hash}"
    cat ./local/luajr/*.lua
} > "$TARGET"
