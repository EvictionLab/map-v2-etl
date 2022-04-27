#!/usr/bin/env bash

###############################################################################
#
#   # `deploy-source.sh`
#
#   This script will check the local `source` directory for any csv files,
#   gzip them, and upload them to S3 for use with the build script.
#
###############################################################################

# load env vars
ENV_FILE=.env.local
if [ -f "$ENV_FILE" ]; then
    echo "loading environment vars from $ENV_FILE"
    export $(echo $(cat $ENV_FILE | sed 's/#.*//g' | sed 's/\r//g' | xargs) | envsubst)
fi

if [ ! -d "./source" ] 
then
    echo "source directory does not exist. create a source directory and place csv files in it." 
    exit 1
fi

# configure aws cli
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

for f in ./source/*.csv
do
  echo "Processing $f file..."
  # take action on each file. $f store current file name
  gzip "$f"
done

aws s3 cp ./source s3://$DATA_INPUT/ --recursive