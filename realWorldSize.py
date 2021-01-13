#!/usr/bin/python
import json, ogr, sys
from argparse import ArgumentParser

parser = ArgumentParser()
parser.add_argument('source')
args = parser.parse_args()

dataSource = ogr.Open(args.source)
envelopes = [
  feature.GetGeometryRef().GetEnvelope()
  for index in range(0, dataSource.GetLayerCount())
  for feature in dataSource.GetLayerByIndex(index)
]
(lefts, rights, bottoms, tops) = list(map(list, zip(*envelopes)))

json.dump({
  "width": max(rights) - min(lefts),
  "height": max(tops) - min(bottoms),
}, sys.stdout)