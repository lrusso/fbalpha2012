#!/bin/bash

# Builds FB Alpha 2012 as asm.js (pure JavaScript, no WebAssembly) for the browser. The
# Emscripten SDK has to be set up already (emsdk_env), this script doesn't install or update
# it. The output is svn-current/trunk/fbalpha2012_libretro.js.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/svn-current/trunk"
JOBS="$(sysctl -n hw.ncpu 2> /dev/null || nproc)"
LIBRARY="fbalpha2012_libretro_emscripten.a"
OUTPUT="fbalpha2012_libretro.js"

if ! command -v emcc > /dev/null; then
    echo "emcc not found, set up the Emscripten SDK environment first (emsdk_env)"
    exit 1
fi

echo "Using $(emcc --version | head -n1)"

cd "${BUILD_DIR}"

# A clean build, so the objects and the output always come from these settings.
make -f makefile.libretro platform=emscripten clean
rm -f "${OUTPUT}"
make -f makefile.libretro platform=emscripten -j"${JOBS}"

# The makefile only builds a static library, so it's linked into JavaScript here. WASM=0
# gives asm.js, which Emscripten makes with wasm2js, and the --dealign pass avoids its crash
# on the unaligned memory accesses of the emulator code. ENVIRONMENT=web leaves out the
# code that only runs in Node.
em++ -o "${OUTPUT}" \
    -s WASM=0 \
    -s ENVIRONMENT=web \
    -s INITIAL_MEMORY=268435456 \
    -s DISABLE_EXCEPTION_CATCHING=1 \
    -s ALLOW_TABLE_GROWTH=1 \
    -s FORCE_FILESYSTEM=1 \
    -s BINARYEN_EXTRA_PASSES="--dealign" \
    -s EXPORTED_FUNCTIONS='["_retro_init","_retro_deinit","_retro_api_version","_retro_get_system_info","_retro_get_system_av_info","_retro_set_environment","_retro_set_video_refresh","_retro_set_audio_sample","_retro_set_audio_sample_batch","_retro_set_input_poll","_retro_set_input_state","_retro_set_controller_port_device","_retro_reset","_retro_run","_retro_serialize_size","_retro_serialize","_retro_unserialize","_retro_cheat_reset","_retro_cheat_set","_retro_load_game","_retro_load_game_special","_retro_unload_game","_retro_get_region","_retro_get_memory_data","_retro_get_memory_size","_malloc","_free"]' \
    -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","setValue","getValue","addFunction","removeFunction","UTF8ToString","stringToUTF8","lengthBytesUTF8","FS","HEAPU8","HEAPU16","HEAPU32","HEAP16"]' \
    -s MODULARIZE=1 \
    -s EXPORT_NAME="FBAlpha2012" \
    -O2 \
    -s USE_ZLIB=1 \
    --no-entry \
    "${LIBRARY}"

# The output is meant for browsers, so it must not load anything with require.
if grep -qE '\brequire\(' "${OUTPUT}"; then
    echo "Error: ${OUTPUT} still has a require"
    exit 1
fi

echo "Done: ${BUILD_DIR}/${OUTPUT}"
