#!/bin/bash

# This packages WaveScript using Petit Chez as the host Scheme implementation.

# Next I need to make it work with ikarus.

# This script runs to build a clean source .deb.  Subsequently, when
# the source package is built, it will need to package everything as a
# BINARY .deb.

#make clean wsparse ikarus boot

#SCRIPTSTART=`pwd`

## TODO: Set the version automatically!!
VER=$WSVER
PACKAGENAME=wavescript

DEBDIR=$REGIMENTD/$PACKAGENAME"_"$VER/

#rm -rf $DEBDIR

#WSDIR=$DEBDIR/debian/tmp/usr/lib/wavescript/$VER
WSDIR=$DEBDIR/

# [2008.08.17] This is fragile, but we want to be minimalist.  It
# copies only the important parts out of the source tree.

function copy_common() {
  mkdir -p $WSDIR/depends
  mkdir -p $WSDIR/src/
  cp -pr $REGIMENTD/install_environment_vars $WSDIR/
  cp -pr $REGIMENTD/lib                      $WSDIR/

  mkdir -p $WSDIR/src/old/chez
  cp -pr $REGIMENTD/src/old/chez/rn-match.ss $WSDIR/src/old/chez/

  mkdir -p $WSDIR/doc/
  cp -pr $REGIMENTD/doc/wavescript_manual    $WSDIR/doc/
  cp -pr $REGIMENTD/doc/wavescript_manpages  $WSDIR/doc/

#   cp -pr $REGIMENTD/src/bin                  $WSDIR/
   cp -pr $REGIMENTD/src/linked_lib           $WSDIR/src/
   cp -pr $REGIMENTD/src/bin                  $WSDIR/src/
   cp -pr $REGIMENTD/src/parser               $WSDIR/src/
   cp -pr $REGIMENTD/src/version              $WSDIR/src/
   cp -a  $REGIMENTD/src/regiment*.ss         $WSDIR/src/

   ## Todo, should instead download the right version of petite from the web.
   ## We should download the version for this architecture.
   cp -pr $REGIMENTD/depends/petite*              $WSDIR/depends/
   cp -pr $REGIMENTD/depends/get_machine_type     $WSDIR/depends/

   cp -a  $REGIMENTD/depends/bos                  $WSDIR/depends/
   cp -pr $REGIMENTD/depends/matpak*              $WSDIR/depends/

  (cd $WSDIR     && ln -s src/bin   ./)
  (cd $WSDIR     && ln -s src/build ./)
  (cd $WSDIR/src && ln -s ../depends  ./)
}

function copy_cleanup() {
  find $WSDIR -name "*.svn" | xargs rm -rf 
  find $WSDIR -name "*~" | xargs rm -rf 
  find $WSDIR -name "#*" | xargs rm -rf 
  find $WSDIR -name "_*" | xargs rm -rf 
}

# This copies all the files necessary to a source package.
function build_src_pkg() {
  echo
  echo PACKAGING REGIMENT/WAVESCRIPT AS A DEBIAN SOURCE PACKAGE
  echo =================================================================
  echo Output directed to $DEBDIR

   copy_common

   cp -pr $REGIMENTD/src/main*                $WSDIR/src/
   cp -pr $REGIMENTD/src/config.ss            $WSDIR/src/
   cp -pr $REGIMENTD/src/legacy_main_chez.ss  $WSDIR/src/
   cp -pr $REGIMENTD/src/temporary*chez*.ss   $WSDIR/src/
   cp -pr $REGIMENTD/src/generate_main*       $WSDIR/src/
   cp -pr $REGIMENTD/src/*.sexp               $WSDIR/src/
   cp -pr $REGIMENTD/src/ws                   $WSDIR/src/
   cp -pr $REGIMENTD/src/Makefile             $WSDIR/src/

  copy_cleanup

  
  cat $DEBDIR/debian/control.in | sed "s/WSVERSIONGOESHERE/$VER/" > $DEBDIR/debian/control
  echo Built debian/control: $DEBDIR/debian/control

  cat > $DEBDIR/debian/changelog <<EOF
wavescript ($VER) unstable; urgency=low

  * Automatically generated package from head revision

 -- Ryan Newton <ryan.newton@alum.mit.edu>  Fri, 15 Aug 2008 17:01:17 -0400

EOF

  cat $DEBDIR/debian/changelog.in >> $DEBDIR/debian/changelog

  cat > $DEBDIR/Makefile <<EOF
#	Note that ikarus must be manually installed on the host system to build this package!
default:
	debuild -S -kWaveScript
	debuild -b -kWaveScript

unsigned:
	debuild -S -uc -us
	debuild -b -uc -us


chez:
	(source install_environment_vars && cd src && make wsparse_zo ikarus boot )
	(export WSVER=$VER; ./package_deb.sh binary-chez)

# Hack: Chez already built ikarus, just package it:
ikarus:
	(export WSVER=$VER; ./package_deb.sh binary-ikarus)
#	(source install_environment_vars && cd src && make wsparse_zo ikarus )

distclean:
	(source install_environment_vars && cd src && make clean )
	rm -rf debian/tmp*
EOF
}

function common_setup() {
  echo
  echo Packaging with "$SUFFIX" as a Debian Binary Package on arch `uname -m`
  echo =================================================================
  REGIMENTD=`pwd`
  rm -rf ./debian/tmp
  mkdir -p ./debian/tmp/usr/bin
  mkdir -p ./debian/tmp/DEBIAN
  mkdir -p ./debian/tmp/usr/lib/$PACKAGENAME/$VER

  cp ./debian/postinst ./debian/tmp/DEBIAN/

  mkdir -p ./debian/tmp/usr/share/doc/$PACKAGENAME"$SUFFIX"/
  cp ./debian/copyright ./debian/tmp/usr/share/doc/$PACKAGENAME"$SUFFIX"/
  cp ./debian/changelog ./debian/tmp/usr/share/doc/$PACKAGENAME"$SUFFIX"/changelog.Debian
  gzip -9               ./debian/tmp/usr/share/doc/$PACKAGENAME"$SUFFIX"/changelog.Debian
#  (cd ./debian/tmp/usr/share/doc/$PACKAGENAME/ && gzip changelog && mv changelog.gz changelog.Debian.gz)

  mkdir -p ./debian/tmp/usr/share/man/man1/  
  cp ./doc/wavescript_manpages/*.1 ./debian/tmp/usr/share/man/man1/
  (gzip -v -9 ./debian/tmp/usr/share/man/man1/*.1)

  for cmd in wsparse ws wsc wsc2 wsmlton regiment; do 
    ln -s /usr/lib/$PACKAGENAME/$VER/bin/$cmd ./debian/tmp/usr/bin/; 
  done
  # assert_regimentd in this case forces it to use the globally installed ver:
  echo "export REGIMENTD=/usr/lib/$PACKAGENAME/$VER/" >  ./debian/tmp/usr/bin/assert_regimentd
  echo 'export IKARUSEXEC="$REGIMENTD/depends/ikarus -b $REGIMENTD/depends/ikarus_lib/ikarus.boot"' >> ./debian/tmp/usr/bin/assert_regimentd
  WSDIR=`pwd`/debian/tmp/usr/lib/$PACKAGENAME/$VER  
  copy_common
}

# We don't want to rely on REGIMENTD pointing to the host system here.
# This must be called from the source package directory (called DEBDIR above)
function build_binary_pkg_chez() {
  SUFFIX="-chez"
  common_setup

  mkdir -p $WSDIR/src/ws/passes/mlton_bkend/
  cp -pr $REGIMENTD/src/ws/passes/mlton_bkend/*   $WSDIR/src/ws/passes/mlton_bkend/
  cp -pr $REGIMENTD/src/build                     $WSDIR/src/
  copy_cleanup

  cp ./debian/tmp/usr/bin/assert_regimentd $WSDIR/bin/assert_regimentd

  # Symlink directly to regiment.chez
  rm -f $WSDIR/bin/regiment 
  ln -s regiment.chez $WSDIR/bin/regiment
  
  # Delete the .zo files, build again client side.
  rm -rf $WSDIR/src/parser/compiled

  cd debian/tmp/
  find -type f | xargs md5sum > ../md5sums
  cd ../../

  mv debian/tmp debian/tmp_chez
  echo =================================================================
}

function build_binary_pkg_ikarus() {
  SUFFIX=""
  common_setup
  rm -rf $WSDIR/depends/petite*
  cp -r /usr/local/lib/ikarus $WSDIR/depends/ikarus_lib
  cp -r /usr/local/bin/ikarus $WSDIR/depends/ikarus

  mkdir -p $WSDIR/src/ws/
  cp -a $REGIMENTD/src/ws/*      $WSDIR/src/ws/
  cp -a $REGIMENTD/src/main*     $WSDIR/src/
  cp -a $REGIMENTD/src/config.ss $WSDIR/src/
  copy_cleanup

  cp ./debian/tmp/usr/bin/assert_regimentd $WSDIR/bin/assert_regimentd

  # Symlink directly to regiment.ikarus
  rm -f $WSDIR/bin/regiment 
  ln -s regiment.ikarus $WSDIR/bin/regiment

  # Delete the .zo files, build again client side.
  rm -rf $WSDIR/src/parser/compiled

  cd debian/tmp/
  ## Hack, let's freshen all the ikarus files to make sure they're newer than source:
  find -name "*.sls" | xargs touch 
  sleep 1
  find -name "*.sls.ikarus-fasl" | xargs touch
  find -type f | xargs md5sum > ../md5sums
  cd ../../
 
  mv debian/tmp debian/tmp_ikarus
  echo =================================================================
}

case $1 in
   "" )              build_src_pkg;;
   "source" )        build_src_pkg;;
   "binary-chez" )   build_binary_pkg_chez;;
   "binary-ikarus" ) build_binary_pkg_ikarus;;
esac


#  tar czf data.tar.gz *

# cd $DEBDIR
# mv $DEBDIR/data/data.tar.gz $DEBDIR/
# rm -rf $DEBDIR/data/

# tar czf control.tar.gz conffiles postinst prerm md5sums
# rm -f conffiles postinst prerm md5sums