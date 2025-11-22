#!/bin/bash
set -e

echo "[DEBUG] Script started."

if [ $# -lt 3 ]; then
  echo "[ERROR] usage: $0 <src-dir> <img-tag> <builder-img> [ --arch <arch> | --platform <platform> ] [ <s2i-args> ... ]"
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
platform=""
s2i_args=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      arch="$2"
      # Convert arch to platform format for consistency
      if [ "$arch" = "amd64" ]; then
        platform="linux/amd64"
      elif [ "$arch" = "arm64" ]; then
        platform="linux/arm64"
      else
        platform="linux/$arch"
      fi
      shift 2
      ;;
    --platform)
      platform="$2"
      shift 2
      ;;
    *)
      s2i_args+=("$1")
      shift
      ;;
  esac
done

srcdir="${s2i_args[0]}"
build_tag="${s2i_args[1]}"
builder="${s2i_args[2]}"
s2i_args=("${s2i_args[@]:3}")  # Remove first 3 mandatory arguments
#Remove --frappe-branch if present
s2i_args=("${s2i_args[@]/--frappe-branch=*}")
[ -d "$srcdir" ] || { echo "[ERROR] $srcdir is not a directory"; exit 1; }

echo "[DEBUG] Source directory: $srcdir"
echo "[DEBUG] Build tag: $build_tag"
echo "[DEBUG] Builder image: $builder"
echo "[DEBUG] Platform: ${platform:-default}"

build_dir=$(mktemp -d -t s2i-XXXX)
dockerfile=$(mktemp -t dockerfile-XXXX)

trap 'rm -rf "$build_dir" "$dockerfile"' EXIT  # Cleanup on exit

echo "[INFO] Running s2i build to generate Dockerfile."
s2i build "$srcdir" "$builder" "${s2i_args[@]}" --as-dockerfile "$dockerfile" || { echo "[ERROR] s2i build failed"; exit 1; }
# Note: --frappe-branch is not passed to s2i build as it is not a valid flag.

# Create upload/src directory and copy source files
mkdir -p upload/src
echo "[INFO] Copying source files to upload/src"
cp -r ${srcdir}/* upload/src/
echo "[DEBUG] Source directory content after copy:"
ls -la upload/src/

echo "[DEBUG] ===== Generated Dockerfile START ====="
cat "$dockerfile"
echo "[DEBUG] ===== Generated Dockerfile END ====="

echo "[DEBUG] ===== Checking if builder image exists ====="
podman image exists "$builder" && echo "[DEBUG] ✓ Builder image '$builder' exists" || echo "[DEBUG] ✗ Builder image '$builder' NOT FOUND"
echo "[DEBUG] ===== Listing images matching builder ====="
podman images "$builder" || echo "[DEBUG] No images found matching '$builder'"
echo "[DEBUG] ===== All podman images ====="
podman images | head -20

echo "[INFO] Running podman build."
if [[ -n "$platform" ]]; then
  podman build --pull=never --platform "$platform" -t "$build_tag" -f "$dockerfile" . --build-arg FRAPPE_BRANCH="$frappe_branch" --no-cache || { echo "[ERROR] podman build failed"; exit 1; }
else
  podman build --pull=never -t "$build_tag" -f "$dockerfile" . --build-arg FRAPPE_BRANCH="$frappe_branch" --no-cache
fi

echo "[DEBUG] Script completed."
