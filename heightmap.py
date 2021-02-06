import json, requests, sys
from osgeo import ogr
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

json.dump(
  {
    "dem": args.dem,
    "cutline": args.cutline,
    "width": args.width,
    "height": args.height,
    "margin": args.margin,
    "srs": args.srs,
    "innerWidth": printLayout['innerSize']['width'],
    "innerHeight": printLayout['innerSize']['height'],
    "marginLeft": printLayout['margin']['width'],
    "marginTop": printLayout['margin']['height'],
  },
  sys.stdout,
)
