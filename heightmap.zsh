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
sourceWidth=`echo $args | jq .sourceWidth -r`
sourceHeight=`echo $args | jq .sourceHeight -r`

size=`
  jq -n "{printOption:{width:$width,height:$height},margin:$margin,source:{width:$sourceWidth,height:$sourceHeight}}" | \
  curl -svXPOST painkiller.arctair.com/layouts/print-layout -H "Content-Type: application/json" -d @-
`
innerWidth=`echo $size | jq .innerSize.width -r`
innerHeight=`echo $size | jq .innerSize.height -r`
marginLeft=`echo $size | jq .margin.width -r`
marginTop=`echo $size | jq .margin.height -r`

echo warping
python - \
  $cutline \
  $srs \
  $innerWidth \
  $innerHeight \
  $dem \
  raster.d/heightmap.project.tif \
  << EOF
import gdal
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('cutline')
parser.add_argument('srid')
parser.add_argument('innerWidth')
parser.add_argument('innerHeight')
parser.add_argument('source')
parser.add_argument('destination')
args = parser.parse_args()

dataSource = gdal.Open(args.source)
band = dataSource.GetRasterBand(1)
noDataValue = band.GetNoDataValue()
del dataSource

gdal.Warp(
  args.destination,
  args.source,
  options = gdal.WarpOptions(
    cutlineDSName = args.cutline,
    cropToCutline = True,
    dstSRS = args.srid,
    srcNodata = noDataValue,
    dstNodata = noDataValue,
    resampleAlg = 'cubic',
    width = args.innerWidth,
    height = args.innerHeight,
  ),
)
EOF

echo translating
python - \
  raster.d/heightmap.project.tif \
  raster.d/heightmap.translate.tif \
  << EOF
import gdal, gdalconst
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('source')
parser.add_argument('destination')
args = parser.parse_args()

dataSource = gdal.Open(args.source)
band = dataSource.GetRasterBand(1)
minimum, maximum = band.ComputeStatistics(0)[0:2]

gdal.Translate(
  args.destination,
  args.source,
  options = gdal.TranslateOptions(
    scaleParams = [[
      minimum,
      maximum,
      8192,
      65534,
    ]],
    outputType = gdalconst.GDT_UInt16,
  ),
)
EOF

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
