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

size=`python - \
  vector.d/cutline.shp \
  $widthInches \
  $heightInches \
  $marginInches \
  $dpi \
  << EOF
import json, ogr
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('cutline')
parser.add_argument('widthInches', type = float)
parser.add_argument('heightInches', type = float)
parser.add_argument('marginInches', type = float)
parser.add_argument('dpi', type = int)
args = parser.parse_args()

driver = ogr.GetDriverByName('ESRI Shapefile')
dataSource = driver.Open(args.cutline)

dataSource = ogr.Open(args.cutline)
layer = dataSource.GetLayer()
for feature in layer:
  geometry = feature.GetGeometryRef()
  (right, left, bottom, top) = geometry.GetEnvelope()
  widthRealWorld = left - right
  heightRealWorld = top - bottom
  widthInchesInner = args.widthInches - args.marginInches * 2.0
  heightInchesInner = args.heightInches - args.marginInches * 2.0
  if widthRealWorld < heightRealWorld:
    height = args.dpi * heightInchesInner
    width = height * widthRealWorld / heightRealWorld
  else:
    width = args.dpi * widthInchesInner
    height = width * heightRealWorld / widthRealWorld
  print(json.dumps({
    'width': width,
    'height': height,
  }))
EOF`

width=`echo $size | jq .width -r`
height=`echo $size | jq .height -r`

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
  raster.d/heightmap.warp.tif \
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
band.ComputeStatistics(0)

gdal.Translate(
  args.destination,
  args.source,
  options = gdal.TranslateOptions(
    scaleParams = [[
      band.GetMinimum(),
      band.GetMaximum(),
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
  raster.d/heightmap.translate.tif \
  raster.d/heightmap.tif \
  << EOF
import gdal, np
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('dpi', type = int)
parser.add_argument('widthInches', type = float)
parser.add_argument('heightInches', type = float)
parser.add_argument('source')
parser.add_argument('destination')
args = parser.parse_args()

translate = gdal.Open(args.source)
innerWidthPixels = translate.RasterXSize
innerHeightPixels = translate.RasterYSize

widthPixels = args.dpi * args.widthInches
heightPixels = args.dpi * args.heightInches

marginLeft=int((widthPixels - innerWidthPixels) / 2)
marginRight=int(widthPixels - innerWidthPixels - marginLeft)
marginTop=int((heightPixels - innerHeightPixels) / 2)
marginBottom=int(heightPixels - innerHeightPixels - marginTop)

heightmapArray = np.pad(
  translate.ReadAsArray(),
  [(marginTop, marginBottom), (marginLeft, marginRight)],
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
  left - xResolution * marginLeft,
  xResolution,
  i0,
  top - yResolution * marginTop,
  i1,
  yResolution,
])
heightmap.SetProjection(translate.GetProjection())
EOF
