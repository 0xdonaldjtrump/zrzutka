// Runs every *.test.js file in this folder.
const fs = require("fs"), path = require("path");
(async () => {
  const files = fs.readdirSync(__dirname).filter((f) => f.endsWith(".test.js")).sort();
  for (const f of files) await require(path.join(__dirname, f))();
  console.log(`\nALL PASSED (${files.length} files)`);
})().catch((e) => { console.error(e); process.exit(1); });
