// Builds index.html (GitHub Pages entry) from src/index.template.html + build.json.
// Usage: npm run compile && node scripts/build.js [contractAddress]
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const b = JSON.parse(fs.readFileSync(path.join(root, "build.json"))).Zrzutka;
const addr = process.argv[2] || "__CONTRACT_ADDRESS__";
const html = fs.readFileSync(path.join(root, "src/index.template.html"), "utf8")
  .replace("__ABI__", JSON.stringify(b.abi))
  .replace("__BYTECODE__", b.bytecode)
  .replace('"__CONTRACT_ADDRESS__"', JSON.stringify(addr));
// syntax check of the inline app script
const js = html.match(/<script>\n\/\* =+ CONFIG[\s\S]*?<\/script>/)[0].replace(/^<script>|<\/script>$/g, "");
new Function(js);
fs.writeFileSync(path.join(root, "index.html"), html);
const ethersUmd = path.join(root, "node_modules/ethers/dist/ethers.umd.min.js");
if (fs.existsSync(ethersUmd)) fs.copyFileSync(ethersUmd, path.join(root, "ethers.umd.min.js"));
console.log("index.html", html.length, "bytes, contract:", addr);
