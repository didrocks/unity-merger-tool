#!/bin/bash
set -ex

[ -z "$dir" ] && echo "No dir directory specified, aborting" && exit 1
[ -z "$trunkrev" ] && echo "No trunkrev specified, aborting" && exit 1
[ -z "$branch" ] && echo "No branch arg specified, aborting" && exit 1

# TODO: make detection of the target pocket
pocket='precise'

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

# Unity specific: add for unity-common a Recommends on checkbox-unity
sed -i 's,Package: unity-common,Package: unity-common\nRecommends: checkbox-unity,' debian/control

# bump the revision to next packaging version and create a source tarball
export DEBFULLNAME='Unity Merger'
export DEBEMAIL=unity.merger@gmail.com
version=`dpkg-parsechangelog | awk '/^Version/ {print $2}' | sed -e "s/\(.*\)-[0-9]ubuntu.*/\1/"`+bzr$((${trunkrev}+1))
version=${version}ubuntu0+${packaging_rev}
sourcename=`dpkg-parsechangelog | awk '/^Source/ {print $2}'`
dch -v $version 'Automatic daily build' -D ${pocket}
cd ..
tar -czf ${sourcename}_${version}.orig.tar.gz trunk
cd $builddir

# Build and make check in a clean environment now
# Use a special local repository per ppa
if [ ! -z "$ppa" ]; then
    export LOCAL_POOL=/var/cache/pbuilder/${pocket}-${ppa/\//--}
    [ ! -d "$LOCAL_POOL" ] && mkdir $LOCAL_POOL
    pdebuild --buildresult $LOCAL_POOL -- --bindmounts $LOCAL_POOL
else
    pdebuild
fi

# SIGN and DPUT the package if a ppa is provided
if [ ! -z "$ppa" ]; then
    # build an orig.tar.gz file and push it to launchpad
    debuild -S -d
    cd ..
    dput ppa:${ppa} *_source.changes || true
fi
