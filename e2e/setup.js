// e2e helper: deploys MockUSDC on local ganache and mints test USDC to all accounts
const { ethers } = require("ethers");
const b = require("../build.json");
(async () => {
  const p = new ethers.JsonRpcProvider("http://127.0.0.1:8545");
  const accs = await p.listAccounts();
  const s = accs[0];
  const f = new ethers.ContractFactory(b.MockUSDC.abi, b.MockUSDC.bytecode, s);
  const u = await f.deploy(); await u.waitForDeployment();
  for (const a of accs) await (await u.mint(a.address, 1000n * 10n ** 6n)).wait();
  console.log(JSON.stringify({ usdc: await u.getAddress(), accounts: accs.map(a => a.address) }));
})();
