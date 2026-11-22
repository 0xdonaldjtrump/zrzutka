# Deploying your own Zrzutka

1. Open the site (GitHub Pages) in Chrome with MetaMask, on the **Base** network, with a little ETH for gas (~$0.10).
2. If no contract is configured, the page shows **"Połącz portfel i wdroż" / "Connect wallet & deploy"**.
3. Confirm the deployment in MetaMask. The wallet that deploys becomes the **owner** — it receives the platform fees
   and sees the **Admin** button.
4. Copy the contract address shown after deployment and build the page with it:

```bash
npm install
npm run compile
node scripts/build.js 0xYourContractAddress
```

5. Commit the new `index.html`. GitHub Pages serves it at `https://<user>.github.io/zrzutka/`.

The constructor takes one argument — the USDC token address. The page passes native Base USDC
`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` automatically.

## Local development

```bash
npm install
npm run compile      # solc 0.8.24, optimizer 200, evm paris → build.json
npm test             # 8 test files on an in-memory ganache chain
node scripts/build.js
```

End-to-end UI test (Playwright + ganache, see `e2e/`):

```bash
npx ganache --chain.chainId 8453 --wallet.totalAccounts 6 -q &
node e2e/setup.js > e2e/env.json
python3 -m http.server 8002 &
python3 e2e/run.py
```
