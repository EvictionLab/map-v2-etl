/**
 * This script re-formats the eviction lab source data from long to wide format
 * with columns for each year
 * Usage: node shape-data.mjs <input-file> <output-file>
 */

const fs = require("fs");
const Papa = require("papaparse");
const d3 = require("d3");
const colMapJson = require(`../assets/column-map-${process.env.DATA_INPUT_TYPE}.json`);

// row identifier column name (raw is "GEOID", modelled is "id")
const ROW_ID = process.env.DATA_INPUT_TYPE === "modelled" ? "id" : "GEOID";

// map of input column names to output column names
const COL_MAP = colMapJson;

// columns that do not change by year
const NO_YEAR_COLS = ["id", "name", "parent_location"];

// time interval to provide updates
const INTERVAL = 10;

/**
 * Parses the row, returning values with a year prefix
 * @param {object} row
 * @returns {object}
 */
const parser = (row) => {
  const year = row["year"].slice(-2);
  const newRow = Object.keys(row).reduce((acc, key) => {
    // skip this column if it's not in the map
    if (!COL_MAP[key]) return acc;
    // do not add the year suffix for NO_YEAR_COLS
    if (NO_YEAR_COLS.indexOf(key) > -1) {
      acc[COL_MAP[key]] = row[key];
      return acc;
    }
    // add the property + year (e.g. ef_00)
    const yearKey = [COL_MAP[key], year].join("-");
    acc[yearKey] = row[key];
    return acc;
  }, {});
  return newRow;
};

/**
 * Comparator for string keys for sorting GEOIDs
 */
const sortKeys = (a, b) => {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
};

/**
 * Returns current timestamp in seconds
 */
const getTimestamp = () => {
  return Math.floor(Date.now() / 1000);
};

// tracks time of the last status message
let lastUpdate = getTimestamp();
// counts the number of parsed rows for status updates
let count = 0;
// tracks the start time for total elapsed time updates
const startTime = lastUpdate;
// contains the parsed data
const result = {};
// options for PapaParse
const options = { header: true };
// input filename from command line (first arg)
const filename = process.argv[2];
// output filename from command line (second arg)
const output = process.argv[3];
// create an output stream to write to file, or stdout if no output file
const outputStream = output ? fs.createWriteStream(output) : process.stdout;

fs.createReadStream(filename, { encoding: "utf8" })
  .pipe(Papa.parse(Papa.NODE_STREAM_INPUT, options))
  .on("data", (data) => {
    const time = getTimestamp();
    count = count + 1;
    // update every 10s (only if output is not stdout)
    if (output && time - lastUpdate >= INTERVAL) {
      const elapsed = Math.round(time - startTime) + "s";
      const updateString = `${elapsed}: ${count} rows parsed`;
      console.log(updateString);
      lastUpdate = time;
    }
    const id = data[ROW_ID];
    const row = parser(data);
    // create the entry for the GEOID if it doesn't exist
    if (!result[id]) result[id] = { GEOID: id };
    // extent the GEOID entry with the row values
    result[id] = { ...result[id], ...row };
  })
  .on("end", () => {
    // get all of the GEOIDs in the resulting dataset, and sort them
    const geoidKeys = Object.keys(result).sort(sortKeys);
    // get all of the columns in the first entry
    const columnKeys = Object.keys(result[geoidKeys[0]]);
    // write the header row
    outputStream.write(columnKeys.join(",") + "\n");
    for (let i = 0; i < geoidKeys.length; i++) {
      const time = getTimestamp();
      // update every 10s (only if output is not stdout)
      if (output && time - lastUpdate >= INTERVAL) {
        const elapsed = Math.round(time - startTime) + "s";
        const updateString = `${elapsed}: ${i} rows written to file`;
        console.log(updateString);
        lastUpdate = time;
      }
      // the GEOID for this row
      const key = geoidKeys[i];
      // pull the data for the row, ensure they are in the same order as the header row
      const rowData = columnKeys.map((col) => result[key][col]);
      // write the row to the output stream
      outputStream.write(d3.csvFormatRow(rowData) + "\n");
    }
  });
