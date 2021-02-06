#!/bin/zsh
args=`python ~/ws/painkillergis/heightmap/heightmap.py "$@"`

if [[ "$?" != "0" ]] ; then
  exit 1
fi
