#!/bin/bash
set -e
echo "[DEBUG] Script started."

# Display usage information if the number of arguments is less than 3
if [ $# -lt 3 ]; then
  echo "[ERROR] usage: $0 <src-dir> <img-tag> <builder-img> [ <s2i-args> ... ]"
  echo ""
  echo "Parameters:"
  echo " <src-dir> : Path to the source directory containing the application code."
  echo " <img-tag> : Tag for the resulting container image."
  echo " <builder-img> : The S2I builder image to use."
  echo " <s2i-args> : (Optional) Additional arguments to pass to the s2i build command."
  exit 1
fi

fail() {
  echo "[ERROR] $1"
  exit 1
}

srcdir=$1
shift
[ -d "$srcdir" ] || fail "$srcdir not a directory"
echo "[DEBUG] Source directory: $srcdir"

buildtag=$1
shift
echo "[DEBUG] Build tag: $buildtag"

builder=$1
shift
[ -n "$builder" ] || fail "Builder image must be specified"
echo "[DEBUG] Builder image: $builder"

origdir=$(pwd)
echo "[DEBUG] Original directory: $origdir"

# Get absolute path to source directory
cd $srcdir
srcdir=$(pwd)
cd $origdir
echo "[DEBUG] Absolute source directory: $srcdir"

# Create build directory
blddir=$(mktemp -d -t s2i-XXXX)
[ -d "$blddir" ] || fail "$blddir not a directory"
echo "[DEBUG] Build directory: $blddir"

dockerfile=$(mktemp -t dockerfile-XXXX)
[ -f "$dockerfile" ] || fail "$dockerfile not a filename"
echo "[DEBUG] Dockerfile path: $dockerfile"

echo "[INFO] Building in directory $blddir"

# Change to build directory
cd $blddir

# Debug: Check if builder image exists
echo "[DEBUG] Checking if builder image exists:"
podman images | grep "$builder" || echo "Builder image not found!"

# Debug: Check source directory content
echo "[DEBUG] Checking source directory content:"
find "$srcdir" -type f | head -n 10

# Run s2i build with the specified builder image
echo "[INFO] Running s2i build to generate Dockerfile."
s2i build "$srcdir" "$builder" "$@" --as-dockerfile $dockerfile

# Create upload/src directory and copy source files
mkdir -p upload/src
echo "[INFO] Copying source files to upload/src"
cp -r ${srcdir}/* upload/src/
echo "[DEBUG] Source directory content after copy:"
ls -la upload/src/

# Show the generated Dockerfile for debugging
echo "[DEBUG] Generated Dockerfile content:"
cat $dockerfile

echo "[INFO] Running podman build."
podman build -t $buildtag -f $dockerfile . --no-cache

echo "[INFO] Cleaning up temporary files."
cd $origdir
rm -rf $blddir $dockerfile
echo "[DEBUG] Script completed."