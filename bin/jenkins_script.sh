#!/bin/bash
set -ex

[ -z "$dir" ] && echo "No dir directory specified, aborting" && exit 1
[ -z "$trunkrev" ] && echo "No trunkrev specified, aborting" && exit 1
[ -z "$branch" ] && echo "No branch arg specified, aborting" && exit 1

[ ! -z "${WORKSPACE}" ] && rm -rf ${WORKSPACE}/*
# create and copy builddir with packaging
builddir=${WORKSPACE}/trunk
cp -r --preserve=mode,timestamps $dir $builddir || true # because .bzr isn't readable for another user
rm -rf $builddir/.bzr # in case we read it with the same user
# support packages containing the debian directory
if [ -d "${builddir}/debian" ]; then
    packaging_rev='inline'
else
    bzr branch $branch ${WORKSPACE}/packaging
    cd ${WORKSPACE}/packaging
    packaging_rev=`bzr log -c -1 | awk '/^revno/ {print $2}'`
    mv debian/ $builddir/
fi
cd $builddir

# prepare the source branch as if it was released
if [ -f autogen.sh ]; then
    cp /usr/share/gtk-doc/data/gtk-doc.make .
    # hack for nux as there is doxygen
    if [ -f doxygen-include.am ]; then
         rm doxygen-include.am
         sed -i 's/include doxygen-include.am/#include doxygen-include.am/' Makefile.am
         sed -i 's/DX_/#DX_/' configure.ac
    fi
    autoreconf -f -i
    aclocal
    grep -q IT_PROG_INTLTOOL configure.* && intltoolize
fi

# ignore abi/api change for the build (don't force the package symbol file to be up to date)
sed -i 's,^\(#\!.*\),\1\nexport DPKG_GENSYMBOLS_CHECK_LEVEL=0,' debian/rules

# bump the revision to next packaging version (/!\ target oneiric harcoded there) and create a source tarball
export DEBFULLNAME='Unity Merger'
export DEBEMAIL=unity.merger@gmail.com
version=`dpkg-parsechangelog | awk '/^Version/ {print $2}' | sed -e "s/\(.*\)-[0-9]ubuntu.*/\1/"`+bzr${trunkrev}
version=${version}ubuntu0+${packaging_rev}
sourcename=`dpkg-parsechangelog | awk '/^Source/ {print $2}'`
dch -v $version 'Automatic daily build' -D oneiric
cd ..
# TODO: maybe separate this script in two steps so that we can have some hooks like this one for unity:
# sed -i 's/^Recommends: unity-lens-applications/Recommends: checkbox-unity,\n            unity-lens-applications/' debian/control
tar -czf ${sourcename}_${version}.orig.tar.gz trunk
cd $builddir

# Build and make check in a clean environment now
pdebuild

# SIGN and DPUT the package
# build an orig.tar.gz file and push it to launchpad
debuild -S -d
cd ..
dput ppa:unity-team/staging *_source.changes || true
python wait_on_ppa.py -s ${sourcename} -v ${version}
