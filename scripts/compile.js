const solc=require("solc"),fs=require("fs"),path=require("path");
const files=fs.readdirSync("contracts").filter(f=>f.endsWith(".sol"));
const sources={}; for(const f of files) sources[f]={content:fs.readFileSync("contracts/"+f,"utf8")};
function findImports(p){ for(const base of ["contracts/","node_modules/"]){ const fp=path.join(base,p); if(fs.existsSync(fp)) return {contents:fs.readFileSync(fp,"utf8")}; } return {error:"not found "+p}; }
const input={language:"Solidity",sources,settings:{optimizer:{enabled:true,runs:200},evmVersion:"paris",outputSelection:{"*":{"*":["abi","evm.bytecode.object","evm.deployedBytecode.object"]}}}};
const out=JSON.parse(solc.compile(JSON.stringify(input),{import:findImports}));
let bad=false; (out.errors||[]).forEach(e=>{ if(e.severity==="error") bad=true; if(e.severity==="error"||!/SPDX|unreachable/.test(e.message)) console.log(e.severity,e.formattedMessage.split("\n").slice(0,4).join(" | ")); });
if(bad) process.exit(1);
const build={};
for(const [f,cs] of Object.entries(out.contracts)) for(const [n,c] of Object.entries(cs)) if(["Zrzutka","MockUSDC"].includes(n)) build[n]={abi:c.abi,bytecode:"0x"+c.evm.bytecode.object,size:c.evm.deployedBytecode.object.length/2};
fs.writeFileSync("build.json",JSON.stringify(build));
console.log("Zrzutka runtime bytes:",build.Zrzutka.size,"(limit 24576) | solc",solc.version());
