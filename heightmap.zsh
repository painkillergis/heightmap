#!/bin/zsh
widthInches=8.0
heightInches=10.0
marginInches=0.5
dpi=300

widthInchesLessMargin=$((widthInches-marginInches*2.0))
heightInchesLessMargin=$((heightInches-marginInches*2.0))

echo projecting and cutting
python - \
  shp.d/cutline.geojson \
  EPSG:6502 \
  raster.d/heightmap.vrt \
  raster.d/heightmap.project.tif \
  << EOF
import gdal
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('cutline')
parser.add_argument('srid')
parser.add_argument('source')
parser.add_argument('destination')
args = parser.parse_args()

gdal.Warp(
  args.destination,
  args.source,
  options = gdal.WarpOptions(
    cutlineDSName = args.cutline,
    cropToCutline = True,
    dstSRS = args.srid,
  ),
)
EOF

widthMeters=2742.0
heightMeters=3130.0

if [ "`echo "$widthMeters\n$heightMeters" | sort -g | head -1`" = "$widthMeters" ] ; then
  widthPixels=$((dpi*widthInchesLessMargin))
  heightPixels=$((widthPixels*heightMeters/widthMeters))
else
  echo landscape orientation not implemented
  exit 1
fi

echo warping
python - \
  ${widthPixels%.*} \
  ${heightPixels%.*} \
  raster.d/heightmap.project.tif \
  raster.d/heightmap.warp.tif \
  << EOF
import gdal
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('nextWidthPixels', type = int)
parser.add_argument('nextHeightPixels', type = int)
parser.add_argument('source')
parser.add_argument('destination')
args = parser.parse_args()

gdal.Warp(
  args.destination,
  args.source,
  options = gdal.WarpOptions(
    resampleAlg = 'cubic',
    width = args.nextWidthPixels,
    height = args.nextHeightPixels,
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
dpi = args.dpi
widthInches = args.widthInches
heightInches = args.heightInches
widthPixels = translate.RasterXSize
heightPixels = translate.RasterYSize
marginLeft=(dpi * widthInches - widthPixels) / 2
marginTop=(dpi * heightInches - heightPixels) / 2
heightmapArray = np.pad(
  translate.ReadAsArray(),
  [(int(marginTop),), (int(marginLeft),)],
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
