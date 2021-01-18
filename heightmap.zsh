#!/bin/zsh
if [ -z "$dem" ] ; then
  echo dem is required
  exit 1
fi
if [ -z "$cutline" ] ; then
  echo cutline is required
  exit 1
fi
if [ -z "$widthInches" ] ; then
  echo widthInches is required
  exit 1
fi
if [ -z "$heightInches" ] ; then
  echo heightInches is required
  exit 1
fi
if [ -z "$marginInches" ] ; then
  echo marginInches is required
  exit 1
fi
if [ -z "$dpi" ] ; then
  echo dpi is required
  exit 1
fi

sourceSize=`python \
  ~/ws/painkiller/heightmap/vectorSize.py \
  $cutline`
sourceWidth=`echo $sourceSize | jq .width -r`
sourceHeight=`echo $sourceSize | jq .height -r`

inset=`jq -n "{width:$((widthInches*dpi)),height:$((heightInches*dpi)),margin:$((marginInches*dpi)),sourceWidth:$sourceWidth,sourceHeight:$sourceHeight}"`

size=`curl -sXPOST painkiller.arctair.com/layouts/inset -H "Content-Type: application/json" -d "$inset"`
width=`echo $size | jq .innerWidth -r`
height=`echo $size | jq .innerHeight -r`
marginLeft=`echo $size | jq .marginLeft -r`
marginTop=`echo $size | jq .marginTop -r`

echo warping
python - \
  $cutline \
  EPSG:6502 \
  ${width%.*} \
  ${height%.*} \
  $dem \
  raster.d/heightmap.project.tif \
  << EOF
import gdal
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('cutline')
parser.add_argument('srid')
parser.add_argument('width')
parser.add_argument('height')
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
    width = args.width,
    height = args.height,
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
  $dpi \
  $widthInches \
  $heightInches \
  $marginLeft \
  $marginTop \
  raster.d/heightmap.translate.tif \
  raster.d/heightmap.tif \
  << EOF
import gdal, np
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('dpi', type = int)
parser.add_argument('widthInches', type = float)
parser.add_argument('heightInches', type = float)
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
