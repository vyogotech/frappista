#!/bin/bash
set -e

echo "[DEBUG] Script started."

if [ $# -lt 3 ]; then
  echo "[ERROR] usage: $0 <src-dir> <img-tag> <builder-img> [ --arch <arch> ] [ <s2i-args> ... ]"
  exit 1
fi
frappe_branch=""

# Check for FRAPPE_BRANCH argument
for arg in "$@"; do
  if [[ "$arg" == --frappe-branch=* ]]; then
    frappe_branch="${arg#*=}"
    break
  fi
done

if [[ -n "$frappe_branch" ]]; then
  echo "[DEBUG] Frappe branch specified: $frappe_branch"
else
  echo "[DEBUG] No Frappe branch specified. Using default."
fi
arch=""
s2i_args=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      arch="$2"
      shift 2
      ;;
    *)
      s2i_args+=("$1")
      shift
      ;;
  esac
done

srcdir="${s2i_args[0]}"
buildtag="${s2i_args[1]}"
builder="${s2i_args[2]}"
s2i_args=("${s2i_args[@]:3}")  # Remove first 3 mandatory arguments

[ -d "$srcdir" ] || { echo "[ERROR] $srcdir is not a directory"; exit 1; }

echo "[DEBUG] Source directory: $srcdir"
echo "[DEBUG] Build tag: $buildtag"
echo "[DEBUG] Builder image: $builder"
echo "[DEBUG] Architecture: ${arch:-default}"

blddir=$(mktemp -d -t s2i-XXXX)
dockerfile=$(mktemp -t dockerfile-XXXX)

trap 'rm -rf "$blddir" "$dockerfile"' EXIT  # Cleanup on exit

echo "[INFO] Running s2i build to generate Dockerfile."
s2i build "$srcdir" "$builder" "${s2i_args[@]}" --as-dockerfile "$dockerfile"

# Create upload/src directory and copy source files
mkdir -p upload/src
echo "[INFO] Copying source files to upload/src"
cp -r ${srcdir}/* upload/src/
echo "[DEBUG] Source directory content after copy:"
ls -la upload/src/

echo "[INFO] Running podman build."
if [[ -n "$arch" ]]; then
  podman build --arch "$arch" -t "$buildtag" -f "$dockerfile" . --build-arg FRAPPE_BRANCH="$frappe_branch" --no-cache
else
  podman build --arch "$arch" -t "$buildtag" -f "$dockerfile" . --build-arg FRAPPE_BRANCH="$frappe_branch" --no-cache
fi

echo "[DEBUG] Script completed."
