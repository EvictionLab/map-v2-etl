# Eviction Lab ETL 2.0 Pipeline

This pipeline loads Eviction Lab map 2.0 data and performs the following actions:

- changes column names to short format (data optimization)
- transforms the input csv to a wide format csv with short format column names
- extracts the extents for each data metrics by year (as well as the bottom 1% and top 1% values to eliminate outliers)
  - this data is used to determine the scales for each metric
- generates vector tilesets for choropleth and bubble layers for each region
  - to keep data sizes within limits, each tileset contains 10 years of data. e.g. block-groups-00.mbtiles will contain data for 2000-2009, and block-groups-10.mbtiles will contain data for 2010-2019.

## Getting Started

### Install requirements

> Note: you can use the docker container to run the ETL pipeline instead of installing the requirements locally.

1. install [aws-cli](https://aws.amazon.com/cli/) and configure with credentials that have access to the eviction lab S3 buckets.
2. install [tippecanoe](https://github.com/mapbox/tippecanoe)
3. install [csvkit](https://csvkit.readthedocs.io/en/latest/tutorial/1_getting_started.html#installing-csvkit)
4. install [mapshaper](https://github.com/mbloch/mapshaper)
5. install node dependencies with `npm install`

### Configure environment vars

copy `.env` to `.env.local` and add configuration for AWS CLI, S3 input bucket, and S3 output buckets.

**defaults:**

```
AWS_ACCESS_ID=
AWS_SECRET_KEY=
DATA_INPUT="eviction-lab-etl-data/2018-12-14"
GEOJSON_INPUT="eviction-lab-etl-data/census"
TILESET_OUTPUT="eviction-lab-tilesets/2022-03"
DATA_OUTPUT="eviction-lab-etl-data/2022-03"
```

## Using Docker

Clone the repository then build the docker image with:

```
docker build -t eviction-lab-etl .
```

once the dockerfile is finished building, run it with:

```
docker run -it --env-file .env.local eviction-lab-etl
```

this will put you in a command line shell where you can run the `./build.sh` script with your preferred options (outlined below)

## Building the tilesets + data

> **Warning:** if you are deploying, ensure the`DATA_OUTPUT` and `TILESET_OUTPUT` in .env.local will not overwrite the version currently used in production.

Use the `build.sh` script to build tilesets and static data.

```sh
Usage: build.sh [-t] [-d] [-r region]
  -r: region to build (default: all)
  -e: build a static csv that contains the extents for each variable for each region
  -t: build tilesets
  -d: deploy output to s3
```

**Example:** build and deploy tilesets and static data (including extents) for all regions

```
./build.sh -d -e -t
```

**Example:** build tracts tileset locally (do not deploy to S3)

```
./build.sh -t -r tracts
```

## Previewing Tilesets

After running a build, there will be a local copy of the data and tilesets (.mbtiles) in the `build` folder. You can use [tileserver-gl](https://github.com/maptiler/tileserver-gl) to preview the tilesets locally.

> Note: `tileserver-gl` only works with node 10. you will want to install node 10 with `nvm`: `nvm install 10`

**Example:** preview the census tracts for 2010-2019 tileset locally

```
tileserver-gl ./build/tracts-10.mbtiles
```

then open http://localhost:8080/ to view the tileset.
