#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: build-wsl2.sh [options]

Options:
  -a, --arch <i686|x86_64|x86_64_v3|aarch64>  Target architecture (default: x86_64)
  -t, --target <mpv|mpv-release>             Build target (default: mpv)
  -p, --package                              Also run mpv-packaging after the build
  -b, --build-dir <path>                     Build directory (default: build_wsl2_<arch>)
  -c, --clean                                Remove build directory before configuring
  -h, --help                                 Show this help

Examples:
  ./scripts/build-wsl2.sh
  ./scripts/build-wsl2.sh --arch i686
  ./scripts/build-wsl2.sh --target mpv-release --package
EOF
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
arch="x86_64"
target="mpv"
build_dir=""
run_package=0
clean_build=0

while (($#)); do
    case "$1" in
        -a|--arch)
            arch=${2:-}
            shift 2
            ;;
        -t|--target)
            target=${2:-}
            shift 2
            ;;
        -b|--build-dir)
            build_dir=${2:-}
            shift 2
            ;;
        -p|--package)
            run_package=1
            shift
            ;;
        -c|--clean)
            clean_build=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "$arch" in
    i686|x86_64|x86_64_v3|aarch64)
        ;;
    *)
        echo "Unsupported architecture: $arch" >&2
        exit 1
        ;;
esac

case "$target" in
    mpv|mpv-release)
        ;;
    *)
        echo "Unsupported target: $target" >&2
        exit 1
        ;;
esac

if [[ -z "$build_dir" ]]; then
    build_dir="$repo_root/build_wsl2_${arch}"
fi

for cmd in cmake ninja meson git bash 7z; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 1
    fi
done

if [[ "$clean_build" -eq 1 ]]; then
    rm -rf "$build_dir"
fi

mkdir -p "$repo_root/clang_root" "$repo_root/src_packages"

cmake_args=(
    -DTARGET_ARCH="${arch}-w64-mingw32"
    -DCOMPILER_TOOLCHAIN=clang
    -DCMAKE_INSTALL_PREFIX="$repo_root/clang_root"
    -DMINGW_INSTALL_PREFIX="$build_dir/${arch}-w64-mingw32"
    -DSINGLE_SOURCE_LOCATION="$repo_root/src_packages"
    -DRUSTUP_LOCATION="$repo_root/clang_root/install_rustup"
    -DENABLE_CCACHE=ON
    -DCLANG_PACKAGES_LTO=ON
    -G Ninja
    --fresh
    -B "$build_dir"
    -S "$repo_root"
)

echo "Configuring build directory: $build_dir"
cmake "${cmake_args[@]}"

echo "Downloading sources"
ninja -C "$build_dir" download || true

echo "Updating repository packages"
ninja -C "$build_dir" update

echo "Building target: $target"
ninja -C "$build_dir" "$target"

if [[ "$run_package" -eq 1 ]]; then
    echo "Packaging mpv"
    ninja -C "$build_dir" mpv-packaging
fi

echo "Build finished"
echo "Artifacts are under: $build_dir"
if [[ "$target" == "mpv-release" ]]; then
    echo "Release package folders are renamed under $build_dir/mpv-${arch}*"
else
    echo "mpv package folders are renamed under $build_dir/mpv-${arch}*"
fi