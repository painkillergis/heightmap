#!/usr/bin/env python
import json, np, requests, sys
from osgeo import gdal, gdalconst, ogr
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('dem')
parser.add_argument('cutline')
parser.add_argument('width')
parser.add_argument('height')
parser.add_argument('margin')
parser.add_argument('srs')
args = parser.parse_args()

cutlineDataSource = ogr.Open(args.cutline)

layers = [
  cutlineDataSource.GetLayerByIndex(index)
  for index in range(0, cutlineDataSource.GetLayerCount())
]

envelopes = [
  feature.GetGeometryRef().GetEnvelope()
  for layer in layers
  for feature in layer
]

(lefts, rights, bottoms, tops) = list(map(list, zip(*envelopes)))

printLayout = requests.post(
  'http://painkiller.arctair.com/layouts/print-layout',
  json = {
    "printOption": {
      "width": args.width,
      "height": args.height,
    },
    "source": {
      "width": max(rights) - min(lefts),
      "height": max(tops) - min(bottoms),
    },
    "margin": args.margin,
  },
) \
  .json()

dataSource = gdal.Open(args.dem)
band = dataSource.GetRasterBand(1)
noDataValue = band.GetNoDataValue()
del dataSource

gdal.Warp(
  'raster.d/heightmap.project.tif',
  args.dem,
  options = gdal.WarpOptions(
    cutlineDSName = args.cutline,
    cropToCutline = True,
    dstSRS = args.srs,
    srcNodata = noDataValue,
    dstNodata = noDataValue,
    resampleAlg = 'cubic',
    width = printLayout['innerSize']['width'],
    height = printLayout['innerSize']['height'],
  ),
)

projectDataSource = gdal.Open('raster.d/heightmap.project.tif')
band = projectDataSource.GetRasterBand(1)
minimum, maximum = band.ComputeStatistics(0)[0:2]

gdal.Translate(
  'raster.d/heightmap.translate.tif',
  'raster.d/heightmap.project.tif',
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

translate = gdal.Open('raster.d/heightmap.translate.tif')
heightmapArray = np.pad(
  translate.ReadAsArray(),
  [(printLayout['margin']['height'],), (printLayout['margin']['width'],)],
  mode='constant',
  constant_values=0,
)
arrayHeight, arrayWidth = np.shape(heightmapArray)
heightmap = gdal.GetDriverByName('GTiff').Create(
  'raster.d/heightmap.tif',
  arrayWidth,
  arrayHeight,
  1,
  translate.GetRasterBand(1).DataType,
)
heightmap.GetRasterBand(1).WriteArray(heightmapArray)
heightmap.GetRasterBand(1).SetNoDataValue(translate.GetRasterBand(1).GetNoDataValue())
left, xResolution, i0, top, i1, yResolution = translate.GetGeoTransform()
heightmap.SetGeoTransform([
  left - xResolution * printLayout['margin']['width'],
  xResolution,
  i0,
  top - yResolution * printLayout['margin']['height'],
  i1,
  yResolution,
])
heightmap.SetProjection(translate.GetProjection())
