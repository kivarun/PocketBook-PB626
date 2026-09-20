#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf 'PASS: %s\n' "$*"
}

need() {
    command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

echo '==> Checking required tools and headers'
for tool in \
    gcc g++ make cmake ninja pkg-config \
    arm-linux-gnueabihf-gcc arm-linux-gnueabihf-g++ \
    git curl file python3 \
    bc bison flex dtc mkimage qemu-arm \
    cpio rsync xz mkfs.ext4 mkfs.vfat mcopy sfdisk; do
    need "$tool"
done
test -r /usr/include/openssl/ssl.h || fail 'OpenSSL development headers not found'
test -r /usr/include/libelf.h || fail 'libelf development headers not found'
pkg-config --exists sdl2 || fail 'SDL2 development package not found via pkg-config'
pass 'required tools and headers present'

echo '==> Test 1: native C build and run'
mkdir -p "$WORK/native"
cat > "$WORK/native/hello.c" <<'EOF'
#include <stdio.h>
int main(void)
{
    printf("native-c-ok\n");
    return 0;
}
EOF
gcc -O2 -Wall -Wextra -o "$WORK/native/hello" "$WORK/native/hello.c"
out="$("$WORK/native/hello")" || fail "native hello exited with code $?"
[ "$out" = 'native-c-ok' ] || fail "native hello printed unexpected output: $out"
pass 'native C build and run'

echo '==> Test 2: ARM hard-float cross build and QEMU run'
mkdir -p "$WORK/arm"
cat > "$WORK/arm/hello.c" <<'EOF'
#include <stdio.h>
int main(void)
{
    printf("arm-hardfloat-ok\n");
    return 0;
}
EOF
arm-linux-gnueabihf-gcc -O2 -Wall -Wextra -o "$WORK/arm/hello" "$WORK/arm/hello.c"

desc="$(file -b "$WORK/arm/hello")"
case "$desc" in
    *"ELF 32-bit"*ARM*) ;;
    *) fail "cross-built binary is not a 32-bit ARM ELF: $desc" ;;
esac
case "$desc" in
    *ld-linux-armhf*) ;;
    *) fail "cross-built binary does not use the hard-float loader: $desc" ;;
esac

out="$(qemu-arm -L /usr/arm-linux-gnueabihf "$WORK/arm/hello")" \
    || fail "qemu-arm run exited with code $?"
[ "$out" = 'arm-hardfloat-ok' ] || fail "qemu-arm run printed unexpected output: $out"
pass 'ARM hard-float cross build and QEMU user-mode run'

echo '==> Test 3: device tree compile'
mkdir -p "$WORK/dt"
cat > "$WORK/dt/test.dts" <<'EOF'
/dts-v1/;
/ {
    model = "pb626 build env smoke test";
    compatible = "pb626,smoke";
    #address-cells = <1>;
    #size-cells = <1>;
};
EOF
dtc -I dts -O dtb -o "$WORK/dt/test.dtb" "$WORK/dt/test.dts"
[ -s "$WORK/dt/test.dtb" ] || fail 'dtc did not produce a DTB'
magic="$(head -c 4 "$WORK/dt/test.dtb" | od -An -tx1 | tr -d ' \n')"
[ "$magic" = 'd00dfeed' ] || fail "DTB has wrong magic: $magic"
dtc -I dtb -O dts -o "$WORK/dt/roundtrip.dts" "$WORK/dt/test.dtb"
grep -q 'pb626 build env smoke test' "$WORK/dt/roundtrip.dts" \
    || fail 'DTB round-trip lost the model string'
pass 'device tree compile and round-trip'

echo '==> Test 4: U-Boot mkimage'
mkdir -p "$WORK/mkimage"
mkimage -V >/dev/null || fail 'mkimage -V failed'
printf 'pb626 mkimage smoke payload\n' > "$WORK/mkimage/payload.bin"
mkimage -A arm -O u-boot -T kernel -C none -a 0x40000000 -e 0x40000000 \
    -n pb626smoke -d "$WORK/mkimage/payload.bin" "$WORK/mkimage/uImage" >/dev/null
mkimage -l "$WORK/mkimage/uImage" > "$WORK/mkimage/info.txt"
grep -q 'pb626smoke' "$WORK/mkimage/info.txt" || fail 'mkimage image verification failed'
pass 'U-Boot mkimage run'

echo '==> Test 5: CMake + Ninja native build'
mkdir -p "$WORK/cmake"
cat > "$WORK/cmake/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(pb626_smoke CXX)
add_executable(smoke main.cpp)
EOF
cat > "$WORK/cmake/main.cpp" <<'EOF'
#include <iostream>
int main()
{
    std::cout << "cmake-ninja-ok" << std::endl;
    return 0;
}
EOF
cmake -S "$WORK/cmake" -B "$WORK/cmake/build" -G Ninja >/dev/null
cmake --build "$WORK/cmake/build"
out="$("$WORK/cmake/build/smoke")" || fail "cmake smoke binary exited with code $?"
[ "$out" = 'cmake-ninja-ok' ] || fail "cmake smoke binary printed unexpected output: $out"
pass 'CMake + Ninja build and run'

echo '==> Test 6: SDL2 build and dummy video driver run'
mkdir -p "$WORK/sdl2"
cat > "$WORK/sdl2/main.c" <<'EOF'
#include <SDL2/SDL.h>
#include <stdio.h>

int main(void)
{
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window *window = SDL_CreateWindow("pb626-smoke", 0, 0, 64, 64,
                                          SDL_WINDOW_HIDDEN);
    if (!window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    SDL_DestroyWindow(window);
    SDL_Quit();
    printf("sdl2-dummy-ok\n");
    return 0;
}
EOF
gcc -O2 -Wall -Wextra $(pkg-config --cflags sdl2) -o "$WORK/sdl2/sdl2test" \
    "$WORK/sdl2/main.c" $(pkg-config --libs sdl2)
out="$(SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$WORK/sdl2/sdl2test")" \
    || fail "SDL2 smoke binary exited with code $?"
[ "$out" = 'sdl2-dummy-ok' ] || fail "SDL2 smoke binary printed unexpected output: $out"
pass 'SDL2 build and dummy video driver run'

echo
echo 'All build environment smoke tests passed.'
