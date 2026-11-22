// Shared test setup: local ganache chain + MockUSDC (6 decimals, permit) + Zrzutka.
const fs = require("fs"), ganache = require("ganache"), { ethers } = require("ethers");
const MNEMONIC = "myth like bonus scare over problem client lizard pioneer submit female collect";
const b = JSON.parse(fs.readFileSync("build.json"));
const iface = new ethers.Interface(b.Zrzutka.abi);
const USD = (x) => ethers.parseUnits(String(x), 6);
const DAY = 86400;

function assert(cond, msg) { if (!cond) throw new Error("FAIL " + msg); console.log("  ok -", msg); }
async function reverts(promise, name, msg) {
  try { await promise; } catch (e) {
    let got = null;
    try { got = e.data ? iface.parseError(e.data)?.name : null; } catch {}
    if (!got) got = (e.shortMessage || e.message || "").match(/(\w+)\(\)/)?.[1] || e.shortMessage || e.message;
    return assert(!name || got === name || String(got).includes(name), `${msg} (reverts ${name})`);
  }
  throw new Error("FAIL " + msg + " (did not revert)");
}

async function setup() {
  const g = ganache.provider({ logging: { quiet: true }, chain: { hardfork: "shanghai" }, wallet: { mnemonic: MNEMONIC, totalAccounts: 6, defaultBalance: 100 } });
  const provider = new ethers.BrowserProvider(g);
  const signers = await Promise.all([0, 1, 2, 3, 4, 5].map((i) => provider.getSigner(i)));
  const keys = [0, 1, 2, 3, 4, 5].map((i) => ethers.HDNodeWallet.fromPhrase(MNEMONIC, undefined, `m/44'/60'/0'/0/${i}`));
  const usdc = await (await new ethers.ContractFactory(b.MockUSDC.abi, b.MockUSDC.bytecode, signers[0]).deploy()).waitForDeployment();
  const z = await (await new ethers.ContractFactory(b.Zrzutka.abi, b.Zrzutka.bytecode, signers[0]).deploy(await usdc.getAddress())).waitForDeployment();
  for (const s of signers) await (await usdc.mint(await s.getAddress(), USD(10000))).wait();
  const time = async (sec) => { await g.request({ method: "evm_increaseTime", params: [sec] }); await g.request({ method: "evm_mine", params: [] }); };
  const bal = async (addr) => usdc.balanceOf(addr);
  const create = async (signer, goal = 100, days = 10, title = "Test campaign") => {
    await (await z.connect(signer).createCampaign(title, "Description", "https://example.com", USD(goal), days)).wait();
    return Number(await z.campaignsCount());
  };
  const give = async (signer, id, amount, message = "") => {
    await (await usdc.connect(signer).approve(await z.getAddress(), USD(amount))).wait();
    await (await z.connect(signer).contribute(id, USD(amount), message)).wait();
  };
  const permitSig = async (i, amount, deadline) => {
    const owner = keys[i].address;
    const nonce = await usdc.nonces(owner);
    const domain = { name: "USD Coin", version: "1", chainId: (await provider.getNetwork()).chainId, verifyingContract: await usdc.getAddress() };
    const types = { Permit: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }, { name: "value", type: "uint256" }, { name: "nonce", type: "uint256" }, { name: "deadline", type: "uint256" }] };
    const sig = ethers.Signature.from(await keys[i].signTypedData(domain, types, { owner, spender: await z.getAddress(), value: amount, nonce, deadline }));
    return sig;
  };
  return { g, provider, signers, keys, usdc, z, time, bal, create, give, permitSig, USD, DAY };
}

module.exports = { setup, assert, reverts, USD, DAY, ethers };
