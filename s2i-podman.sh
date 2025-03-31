#!/bin/bash
set -e

if [ $# -lt 2 ]; then
    echo "usage: $0 <src-dir> <img-tag> [ <s2i-args> ... ]"
    exit 1
fi

fail() {
    echo $1
    exit 1
}

srcdir=$1
shift
[ -d "$srcdir" ] || fail "$srcdir not a directory"
buildtag=$1
shift

origdir=$(pwd)
cd $srcdir
srcdir=$(pwd)

blddir=$(mktemp -d -t s2i-XXXX)
[ -d "$blddir" ] || fail "$blddir not a directory"
docker=$(mktemp -t dockerfile-XXXX)
[ -f "$docker" ] || fail "$docker not a filename"

echo "building in directory $blddir"
cd $blddir

# build using --as-dockerfile, to create an intermediate dockerfile
# that podman can then build
s2i build . "$@" --as-dockerfile $docker

# the resulting dockerfile expects all src to be staged
# under directory 'upload/src' in the build dir
mkdir -p upload/src
cp -r ${srcdir}/* upload/src/
podman build -t $buildtag -f $docker .

cd $origdir
rm -rf $blddir $docker
