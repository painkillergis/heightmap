#!/usr/bin/python
from osgeo import gdal
from uuid import uuid4
import numpy as np

def intersectDegreeGrid(source):
  tmp = f'/vsimem/{uuid4()}'
  ds = gdal.Rasterize(
    tmp,
    args.source,
    xRes = 1,
    yRes = -1,
    allTouched = True,
    outputBounds = [-180, -90, 180, 90],
    burnValues = 1,
    outputType = gdal.GDT_Byte,
  )

  mask = ds.ReadAsArray()
  ds = None
  gdal.Unlink(tmp)

  y_ind, x_ind = np.where(mask == 1)
  upperLefts = [{ "lat": int(90 - y), "lon": int(-180 + x) } for x, y in zip(x_ind, y_ind)]
  return list(map(upperLeftTo3DepId, upperLefts))

def upperLeftTo3DepId(cell):
  lat = cell.get('lat')
  lon = cell.get('lon')
  return ''.join([
    'n' if lat >= 0 else 's',
    f'{abs(lat):02}',
    'e' if lon >= 0 else 'w',
    f'{abs(lon):03}',
  ])

if __name__ == '__main__':
  from argparse import ArgumentParser
  import sys, json

  parser = ArgumentParser()
  parser.add_argument('source')
  args = parser.parse_args()

  json.dump(intersectDegreeGrid(args.source), sys.stdout, indent=2)