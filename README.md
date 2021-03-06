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
DATA_INPUT_TYPE="raw"
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

## Preparing source data

### 1. Put the source data in the source folder

Before running the build pipeline, you should make sure the source files have been prepared. To prepare the source data, take the source files, place them in the source folder, and name them based on their region.

- states.csv
- counties.csv
- cities.csv
- tracts.csv
- block-groups.csv

### 2. Set the appropriate `.env` variables

In `.env.local`, set the `DATA_INPUT` variable to the S3 bucket + key where the source files should be stored. **Take care not to overwrite any files that are needed.**

**Example:**

```
...
DATA_INPUT="eviction-lab-etl-data/2022-04-25/raw"
...
```

### 3. Run the deploy script

Once the files are in place, run the deploy script to gzip them and upload to the data input S3 bucket.

```sh
./deploy-source.sh
```

## Building the tilesets + data

> **Warning:** if you are deploying, ensure the `DATA_OUTPUT` and `TILESET_OUTPUT` in .env.local will not overwrite the version currently used in production.

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

# Troubleshooting

## How to build modeled vs raw data

To change which dataset gets built, change the `DATA_INPUT_TYPE` env variable between "raw" or "modeled" and update teh `DATA_INPUT` env variable to point at the corresponding source data.

## Why aren't the tiles updating after deploying?

This can happen for a couple reasons:

1. local caching: clear your browser cache
2. cloudfront caching: you may need to invalidate the cache on the cloudfront distribution that serves the tiles
3. you may be pointing at the wrong tileset on the front end. open the "network" tab in your developer tools and ensure that the tiles are coming from the correct endpoint.

## Why are my tilesets missing certain properties?

Properties could be missing for a couple reasons:

1. the property is not included in the `BUBBLE_VARS` or `CHOROPLETH_VARS` arrays in the build script.
2. the data does not have a column corresponding to the property. check the `_proc/$REGION/data.wide.csv` file after running a build and verify the columns exist

## Common Errors

> ColumnIdentifierError: Invalid range %s. Ranges must be two integers separated by a - or : character.

If you get this error, it means the columns in the data file do not match the columns in the build script. Likely a missing column. Check the `_proc/$REGION/data.wide.csv` file and ensure it has columns for each of the variables in the preceding `Creating $TYPE tileset...` log message.
