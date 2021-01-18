#!/usr/bin/python
import json, ogr, sys
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('source')
args = parser.parse_args()

dataSource = ogr.Open(args.source)

layers = [
  dataSource.GetLayerByIndex(index)
  for index in range(0, dataSource.GetLayerCount())
]

envelopes = [
  feature.GetGeometryRef().GetEnvelope()
  for layer in layers
  for feature in layer
]

(lefts, rights, bottoms, tops) = list(map(list, zip(*envelopes)))

json.dump({
  "width": max(rights) - min(lefts),
  "height": max(tops) - min(bottoms),
}, sys.stdout)
