#!/bin/bash
# Build FBAlpha2012 libretro core as asm.js from scratch.
#
# This script can be placed ANYWHERE. It will:
#   1) Install the Emscripten SDK (if emcc is not already available)
#   2) Clone the FBAlpha2012 repo (if not already present next to this script)
#   3) Patch the Makefile for modern Emscripten (.bc -> .a, emcc/em++/emar)
#   4) Compile the static library
#   5) Link to asm.js via wasm2js with the --dealign fix
#
# The key patch: modern Emscripten (4.x+) uses wasm2js for asm.js output,
# which crashes on unaligned memory stores common in emulator code. The fix
# is the binaryen "--dealign" pass that forces all alignment annotations to 1.
#
# Usage:
#   ./build_asmjs.sh                  # Full build (all drivers)
#   ./build_asmjs.sh cps1             # CPS-1 only
#   ./build_asmjs.sh cps2             # CPS-2 only
#   ./build_asmjs.sh cps3             # CPS-3 only
#   ./build_asmjs.sh neogeo           # Neo Geo only

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EMSDK_DIR="$SCRIPT_DIR/emsdk"
TARGET_ARG="${1:-}"
JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Detect if this script is inside the fbalpha2012 repo or standalone
if [ -d "$SCRIPT_DIR/svn-current/trunk" ]; then
    REPO_DIR="$SCRIPT_DIR"
else
    REPO_DIR="$SCRIPT_DIR/fbalpha2012"
fi
BUILD_DIR="$REPO_DIR/svn-current/trunk"

echo "========================================"
echo " FBAlpha2012 asm.js Build (from scratch)"
echo "========================================"
echo ""

# ---- Step 1: Emscripten SDK ----
if command -v emcc &> /dev/null; then
    echo "[1/5] Using existing Emscripten SDK."
else
    if [ ! -d "$EMSDK_DIR" ]; then
        echo "[1/5] Installing Emscripten SDK..."
        git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
        cd "$EMSDK_DIR"
        ./emsdk install latest
        ./emsdk activate latest
        echo ""
    else
        echo "[1/5] Emscripten SDK already installed."
    fi
    source "$EMSDK_DIR/emsdk_env.sh"
fi
echo "Using: $(emcc --version | head -1)"
echo ""

# ---- Step 2: Clone FBAlpha2012 (only if script is standalone) ----
if [ ! -d "$REPO_DIR/svn-current/trunk" ]; then
    echo "[2/5] Cloning FBAlpha2012..."
    git clone https://github.com/libretro/fbalpha2012.git "$REPO_DIR"
    echo ""
else
    echo "[2/5] FBAlpha2012 repo already present."
fi
echo ""

# ---- Step 3: Patch Makefile for modern Emscripten ----
echo "[3/5] Patching Makefile for modern Emscripten..."

MAKEFILE="$BUILD_DIR/makefile.libretro"

# The original emscripten target uses .bc (legacy fastcomp format).
# Patch it to use .a (static archive) with emcc/em++/emar.
if grep -q '$(TARGET_NAME)_libretro_$(platform)\.bc' "$MAKEFILE"; then
    sed -i.bak '/^else ifeq ($(platform), emscripten)/,/^else/{
        s|TARGET := $(TARGET_NAME)_libretro_$(platform)\.bc|TARGET := $(TARGET_NAME)_libretro_$(platform).a\
   CC = emcc\
   CXX = em++\
   AR = emar|
    }' "$MAKEFILE"
    rm -f "$MAKEFILE.bak"
    echo "  Patched: .bc -> .a, added emcc/em++/emar"
else
    echo "  Already patched (or unexpected format), skipping."
fi
echo ""

# ---- Step 4: Compile static library ----
echo "[4/5] Compiling static library..."

cd "$BUILD_DIR"

# Generate required source files if missing
if [ ! -f "src/dep/generated/driverlist.h" ]; then
    echo "  Generating source files..."
    make -f makefile.libretro generate-files
fi

# Determine library name
if [ -n "$TARGET_ARG" ]; then
    LIB_NAME="fbalpha2012_${TARGET_ARG}_libretro_emscripten.a"
    MAKE_ARGS="platform=emscripten target=$TARGET_ARG"
else
    LIB_NAME="fbalpha2012_libretro_emscripten.a"
    MAKE_ARGS="platform=emscripten"
fi

echo "  make -f makefile.libretro $MAKE_ARGS -j$JOBS"
echo ""
make -f makefile.libretro $MAKE_ARGS -j"$JOBS"
echo ""

# ---- Step 5: Link to asm.js ----
echo "[5/5] Linking to asm.js (via wasm2js + dealign)..."
echo ""
echo "  BINARYEN_EXTRA_PASSES=\"--dealign\" forces all memory alignment"
echo "  annotations to 1, fixing the wasm2js assertion:"
echo "  (curr->align == 0 || curr->align == curr->bytes)"
echo ""

em++ -o fbalpha2012_libretro.js \
  -s WASM=0 \
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
  "$LIB_NAME"

echo ""
echo "========================================"
echo " Build complete!"
echo "========================================"
echo ""
echo "Output:"
ls -lh "$BUILD_DIR/fbalpha2012_libretro.js"
ls -lh "$BUILD_DIR/fbalpha2012_libretro.js.mem" 2>/dev/null || true
echo ""
echo "To run: serve svn-current/trunk/ over HTTP and open index.html"
