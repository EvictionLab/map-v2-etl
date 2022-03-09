/**
 * This script reads an input CSV and outputs the min, max, 
 * lowest 1% value (q1), and highest 1% value (q99), and for each column.
 * Usage: node extract-extents.js <input-file> <output-file>
 */

const fs = require("fs");
const Papa = require("papaparse");
const d3 = require("d3");

// skip extents for these columns
const NO_EXTENTS = ["GEOID", "n", "pl"];
// contains the parsed data
const result = [];
// options for PapaParse
const options = { header: true };
// input filename from command line (first arg)
const filename = process.argv[2];
// output filename from command line (second arg)
const output = process.argv[3];

// convert all object properties to numbers
const parser = (data) => {
  return Object.keys(data).reduce((acc, key) => {
    if (data[key] === "" || isNaN(data[key])) return acc;
    acc[key] = Number(data[key]);
    return acc;
  }, {});
};

fs.createReadStream(filename, { encoding: "utf8" })
  .pipe(Papa.parse(Papa.NODE_STREAM_INPUT, options))
  .on("data", (data) => {
    result.push(parser(data));
  })
  .on("end", () => {
    const cols = Object.keys(result[0]).filter(
      (k) => NO_EXTENTS.indexOf(k) === -1
    );
    const extents = [];
    for (let i = 0; i < cols.length; i++) {
      const col = cols[i];
      console.log(`extracting values for ${col}`);
      extents.push({
        id: col,
        min: d3.min(result, (d) => d[col]),
        max: d3.max(result, (d) => d[col]),
        q1: d3.quantile(result, 0.01, (d) => d[col]),
        q99: d3.quantile(result, 0.99, (d) => d[col]),
      });
    }

    if (output)
      fs.writeFileSync(
        output,
        d3.csvFormat(extents, ["id", "min", "max", "q1", "q99"])
      );
    if (!output) process.stdout.write(extents);

  });
