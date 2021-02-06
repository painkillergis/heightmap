#!/bin/zsh
args=`python ~/ws/painkillergis/heightmap/heightmap.py "$@"`

if [[ "$?" != "0" ]] ; then
  exit 1
fi

dem=`echo $args | jq .dem -r`
cutline=`echo $args | jq .cutline -r`
width=`echo $args | jq .width -r`
height=`echo $args | jq .height -r`
margin=`echo $args | jq .margin -r`
srs=`echo $args | jq .srs -r`
innerWidth=`echo $args | jq .innerWidth -r`
innerHeight=`echo $args | jq .innerHeight -r`
marginLeft=`echo $args | jq .marginLeft -r`
marginTop=`echo $args | jq .marginTop -r`

echo padding
python - \
  $marginLeft \
  $marginTop \
  raster.d/heightmap.translate.tif \
  raster.d/heightmap.tif \
  << EOF
import gdal, np
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('marginLeft', type = int)
parser.add_argument('marginTop', type = int)
parser.add_argument('source')
parser.add_argument('destination')
args = parser.parse_args()

translate = gdal.Open(args.source)
heightmapArray = np.pad(
  translate.ReadAsArray(),
  [(args.marginTop,), (args.marginLeft,)],
  mode='constant',
  constant_values=0,
)
arrayHeight, arrayWidth = np.shape(heightmapArray)
heightmap = gdal.GetDriverByName('GTiff').Create(
  args.destination,
  arrayWidth,
  arrayHeight,
  1,
  translate.GetRasterBand(1).DataType,
)
heightmap.GetRasterBand(1).WriteArray(heightmapArray)
heightmap.GetRasterBand(1).SetNoDataValue(translate.GetRasterBand(1).GetNoDataValue())
left, xResolution, i0, top, i1, yResolution = translate.GetGeoTransform()
heightmap.SetGeoTransform([
  left - xResolution * args.marginLeft,
  xResolution,
  i0,
  top - yResolution * args.marginTop,
  i1,
  yResolution,
])
heightmap.SetProjection(translate.GetProjection())
EOF
