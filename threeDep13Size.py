#!/usr/bin/python
import json, ogr, osr, sys
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('source')
args = parser.parse_args()

dataSource = ogr.Open(args.source)

layers = [
  dataSource.GetLayerByIndex(index)
  for index in range(0, dataSource.GetLayerCount())
]

def transform(geometry, spatialRef):
  destination = osr.SpatialReference()
  destination.ImportFromEPSG(4326)
  geometry.Transform(
    osr.CoordinateTransformation(
      spatialRef,
      destination,
    ),
  )
  return geometry

envelopes = [
  transform(feature.GetGeometryRef(), layer.GetSpatialRef()).GetEnvelope()
  for layer in layers
  for feature in layer
]

(lefts, rights, bottoms, tops) = list(map(list, zip(*envelopes)))

width = max(rights) - min(lefts)
height = max(tops) - min(bottoms)

thirdArcSecondPerDegree = 60 * 60 * 3

json.dump({
  "width": width * thirdArcSecondPerDegree,
  "height": height * thirdArcSecondPerDegree,
}, sys.stdout)