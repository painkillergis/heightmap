from osgeo import gdal
from uuid import uuid4
import numpy as np
import sys, json

geojson = sys.stdin.read()

dsPath = f'/vsimem/{uuid4()}'
ds = gdal.Rasterize(
  dsPath,
  geojson,
  xRes = 1,
  yRes = -1,
  allTouched = True,
  outputBounds = [-180, -90, 180, 90],
  burnValues = 1,
  outputType = gdal.GDT_Byte,
)

mask = ds.ReadAsArray()
ds = None
gdal.Unlink(dsPath)

y_ind, x_ind = np.where(mask == 1)
upperLefts = [{ "lat": int(90 - y), "lon": int(-180 + x) } for x, y in zip(x_ind, y_ind)]

json.dump(upperLefts, sys.stdout, indent=2)