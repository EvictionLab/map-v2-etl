#!/usr/bin/env bash
echo $BASH_VERSION

if [[ -z "${AWS_ACCESS_ID}" ]]; then
    printf '%s\n' "Missing AWS_ACCESS_ID environment variable, could not configure AWS CLI." >&2
    exit 1
fi
if [[ -z "${AWS_SECRET_KEY}" ]]; then
    printf '%s\n' "Missing AWS_SECRET_KEY environment variable, could not configure AWS CLI." >&2
    exit 1
fi
aws configure set aws_access_key_id $AWS_ACCESS_ID
aws configure set aws_secret_access_key $AWS_SECRET_KEY
aws configure set default.region us-east-1

# defaults
DEPLOY=0
BUILD_TILESETS=0
BUILD_EXTENTS=0
REGIONS=(states counties cities tracts block-groups)

# declare -A requires bash 4+! 
# if you get an `invalid option` error, you need to update your bash

# each tileset contains 10 years of data
declare -A YEARS
YEARS[0]="00;01;02;03;04;05;06;07;08;09"
YEARS[1]="10;11;12;13;14;15;16;17;18;19"


# process command line args
while getopts 'edtr:h' opt; do
  case "$opt" in
    e)
      BUILD_EXTENTS=1
      ;;
    d)
      DEPLOY=1
      ;;

    t)
      BUILD_TILESETS=1
      ;;

    r)
      arg="$OPTARG"
      REGIONS=($arg)
      ;;

    ?|h)
      echo "Usage: $(basename $0) [-t] [-d] [-r region]"
      echo "  -t: build tilesets"
      echo "  -e: build extents (min / max for each variable)"
      echo "  -d: deploy data and tilesets to S3 endpoint"
      echo "  -r: region to build (default: all)"
      exit 1
      ;;
  esac
done
shift "$(($OPTIND -1))"

# load env vars
export $(echo $(cat .env | sed 's/#.*//g' | sed 's/\r//g' | xargs) | envsubst)

# setup processing folders
rm -rf _proc

for REGION in ${REGIONS[@]}; do

  # download source data
  mkdir -p _proc/$REGION
  mkdir -p build
  echo "fetching $REGION data..."
  aws s3 cp s3://$DATA_INPUT/$REGION.csv.gz ./_proc/$REGION/data.csv.gz
  gunzip -f _proc/$REGION/data.csv.gz

  # shape the data into wide format with short column names
  echo "shaping $REGION data..."
  node --max-old-space-size=4096 ./scripts/shape-data.js ./_proc/$REGION/data.csv ./_proc/$REGION/data.wide.csv
  cp ./_proc/$REGION/data.wide.csv ./build/$REGION.csv

  # extract the min / max values for each column
  if [ $BUILD_EXTENTS = 1 ]; then
    echo "extracting min / max values for $REGION data..."
    node --max-old-space-size=4096 ./scripts/extract-extents.js ./_proc/$REGION/data.wide.csv ./_proc/$REGION/data.extents.csv
    cp ./_proc/$REGION/data.extents.csv ./build/$REGION.extents.csv
  fi

  # deploy static data
  if [ $DEPLOY = 1 ]; then
    echo "uploading static data to S3..."
    # deploy extents if they were built
    if [ $BUILD_EXTENTS = 1 ]; then
      aws s3 cp ./_proc/$REGION/data.extents.csv s3://$DATA_OUTPUT/$REGION-extents.csv
    fi
    aws s3 cp ./_proc/$REGION/data.wide.csv s3://$DATA_OUTPUT/$REGION.csv
  fi

  # build tilesets if flag is set
  if [ $BUILD_TILESETS = 1 ]; then

    # download GeoJSON
    echo "fetching $REGION geojson..."
    aws s3 cp s3://$GEOJSON_INPUT/$REGION.geojson.gz ./_proc/$REGION/shapes.geojson.gz
    gunzip -f _proc/$REGION/shapes.geojson.gz

    # build tilesets by decade
    for DECADE in "${YEARS[@]}"
    do
      # turn semicolon separated list into array (e.g. 00;01;02 => [00,01,02])
      IFS=";" read -r -a YEAR_GROUP <<< "${DECADE}"

      echo "Starting tileset build for $REGION for ${YEAR_GROUP[0]}-${YEAR_GROUP[-1]}..."

      # create a comma separated list of variable names to load in the bubble tileset
      BUBBLE_VARS=("er" "efr")
      BUBBLE_FIELDS="n,pl,"
      for varname in "${BUBBLE_VARS[@]}"
      do
        for suffix in "${YEAR_GROUP[@]}"
        do
          BUBBLE_FIELDS+="${varname}-${suffix},"
        done
      done

      # create metge the bubble fields from the CSV into the GeoJSON +
      # pipe the GeoJSON to the `tippecanoe-json-tool` to format it for use with tippecanoe
      echo "Creating bubble GeoJSON for $REGION..."
      node  --max-old-space-size=8192 `which mapshaper` ./_proc/$REGION/shapes.geojson \
        -filter-fields GEOID \
        -each "id = Number(GEOID)" \
        -join ./_proc/$REGION/data.wide.csv keys=GEOID,GEOID string-fields=GEOID fields=${BUBBLE_FIELDS%?} \
        -points inner \
        -o - format=geojson | \
        tippecanoe-json-tool --extract=GEOID \
          --empty-csv-columns-are-null | \
          LC_ALL=C sort > ./_proc/$REGION/centers.data.geojson

      # tippecanoe options for bubble layers
      declare -A BUBBLE_OPTS
      BUBBLE_OPTS[states]="--maximum-zoom=6 --base-zoom=1"
      BUBBLE_OPTS[counties]="--maximum-zoom=7 --base-zoom=2"
      BUBBLE_OPTS[cities]="--maximum-zoom=8 --base-zoom=6 --drop-densest-as-needed --extend-zooms-if-still-dropping"
      BUBBLE_OPTS[tracts]="--maximum-zoom=12 --base-zoom=7 --drop-densest-as-needed --extend-zooms-if-still-dropping"
      BUBBLE_OPTS[block-groups]="--maximum-zoom=12 --base-zoom=8 --drop-densest-as-needed --extend-zooms-if-still-dropping"

      echo "Generating bubble tileset..."
      tippecanoe -o ./_proc/$REGION/$REGION-centers.mbtiles -f \
        -L $REGION-centers:./_proc/$REGION/centers.data.geojson \
        --read-parallel ${BUBBLE_OPTS[$REGION]} \
        --attribute-type=GEOID:string \
        --use-attribute-for-id=id \
        --empty-csv-columns-are-null

      # create a comma separated list of variable names to load in the choropleth tileset
      CHOROPLETH_VARS=("p" "pr" "pro" "mgr" "mhi" "mpv" "rb" "pw" "paa" "ph" "pai" "pa" "pnp" "pm" "po" "e" "ef" "er" "efr" "lf")
      CHOROPLETH_FIELDS="n,pl,"
      for varname in "${CHOROPLETH_VARS[@]}"
      do
        for suffix in "${YEAR_GROUP[@]}"
        do
          CHOROPLETH_FIELDS+="${varname}-${suffix},"
        done
      done

      # merge the CSV data into the GeoJSON for the region +
      # pipe to `tippecanoe-json-tool` to format the JSON for use with tippecanoe
      echo "Creating choropleth GeoJSON for $REGION..."
      node  --max-old-space-size=8192 `which mapshaper` ./_proc/$REGION/shapes.geojson \
        -filter-fields GEOID \
        -each "id = Number(GEOID)" \
        -join ./_proc/$REGION/data.wide.csv keys=GEOID,GEOID string-fields=GEOID fields=${CHOROPLETH_FIELDS%?} \
        -o - format=geojson | \
        tippecanoe-json-tool --extract=GEOID \
          --empty-csv-columns-are-null | \
          LC_ALL=C sort > ./_proc/$REGION/choropleth.data.geojson

      # tippecanoe options for choropleth layers
      declare -A CHOROPLETH_OPTS
      CHOROPLETH_OPTS[states]="--maximum-zoom=6 --simplification=10 --simplify-only-low-zooms --detect-shared-borders"
      CHOROPLETH_OPTS[counties]="--maximum-zoom=7 --minimum-zoom=1 --coalesce-smallest-as-needed --extend-zooms-if-still-dropping --simplification=10 --simplify-only-low-zooms --detect-shared-borders"
      CHOROPLETH_OPTS[cities]="--maximum-zoom=8 --minimum-zoom=2 --coalesce-smallest-as-needed --extend-zooms-if-still-dropping --simplification=10 --simplify-only-low-zooms --detect-shared-borders"
      CHOROPLETH_OPTS[tracts]="--maximum-zoom=12 --minimum-zoom=7 --coalesce-smallest-as-needed --extend-zooms-if-still-dropping --simplification=10 --simplify-only-low-zooms --detect-shared-borders"
      CHOROPLETH_OPTS[block-groups]="--maximum-zoom=12 --minimum-zoom=8 --coalesce-smallest-as-needed --extend-zooms-if-still-dropping --simplification=10 --simplify-only-low-zooms --detect-shared-borders"

      echo "Generating chorpleth tileset... ${CHOROPLETH_OPTS[$REGION]}"
      tippecanoe -o ./_proc/$REGION/$REGION-choropleth.mbtiles -f \
        -L $REGION:./_proc/$REGION/choropleth.data.geojson \
        --read-parallel ${CHOROPLETH_OPTS[$REGION]} \
        --attribute-type=GEOID:string \
        --use-attribute-for-id=id \
        --empty-csv-columns-are-null

      # join the choropleth and bubble tilesets and put them in the build folder
      echo "Joining $REGION bubble and choropleth tilesets... "
      tile-join --no-tile-size-limit --force -o ./build/$REGION-${DECADE:0:2}.mbtiles ./_proc/$REGION/$REGION-choropleth.mbtiles ./_proc/$REGION/$REGION-centers.mbtiles
      
      # clean up temporary files
      rm ./_proc/$REGION/*.mbtiles
      rm ./_proc/$REGION/*.data.geojson

      # output tileset to directory then copy to S3
      if [ $DEPLOY = 1 ]; then
        echo "preparing .mbtiles for deploy to S3"
        OUTPUT_DIR=./_proc/$REGION/$REGION-${DECADE:0:2}
        tile-join --output-to-directory=$OUTPUT_DIR ./build/$REGION-${DECADE:0:2}.mbtiles
        echo "deploying tileset to S3"
        aws s3 cp $OUTPUT_DIR s3://$TILESET_OUTPUT/$REGION-${DECADE:0:2}/ --recursive \
            --content-type application/x-protobuf \
            --content-encoding gzip \
            --exclude "*.json"
        aws s3 cp $OUTPUT_DIR/metadata.json s3://$TILESET_OUTPUT/$REGION-${DECADE:0:2}/metadata.json \
            --content-type application/json
        rm -rf $OUTPUT_DIR
      fi

    done # end DECADE loop

  fi # end $BUILT_TILESETS = 1 (-t option)

done # end REGION loop

echo "finished running ETL."