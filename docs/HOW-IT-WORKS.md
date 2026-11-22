# How Zrzutka works / Jak działa Zrzutka

## Lifecycle of a campaign

```
            createCampaign()
                   │
                   ▼
   ┌──────────── Active ─────────────┐
   │  contribute() / contributeWith- │
   │  Permit() · postUpdate()        │
   │  editCampaign() · upvote()      │
   │  setFollow() · report()         │
   │  extendDeadline() (once, ≤30d)  │
   └──────┬──────────────┬───────────┘
          │              │
 raised ≥ goal      deadline passed, raised < goal
          │              │   or cancel() / adminCancel()
       claim()           ▼
          │        refund() for every backer
          ▼
       Claimed ──► mintBadge() for every backer (soulbound NFT)
```

## Rules enforced by the contract

| Rule | Value |
|---|---|
| Currency | native USDC on Base (`0x8335…2913`, 6 decimals) |
| Minimum goal | $1 (admin can change) |
| Duration | 1–180 days (admin can change, max 365) |
| Extension | once per campaign, up to 30 days, only before the deadline and while the goal is not reached |
| Platform fee | 1% of a successful campaign, taken on `claim()` (admin can change, hard cap 5%) |
| Refund | 100% of what you paid, no fee, if the campaign failed or was cancelled |
| Claim | creator only, as soon as `raised ≥ goal` (also before the deadline) |
| Badge | one per backer per successful campaign, cannot be transferred |

## Why "all or nothing"?

Classic fundraisers hand the organiser whatever was collected, even if it is far from enough.
Here backers know that their money is used **only if the whole goal is reached** — otherwise it comes back.
That makes it safe to back a school trip, a group gift or a local repair before you know others will join.

## Payment in one signature

USDC supports EIP-2612 `permit`. The app asks your wallet to sign a free, off-chain permit and then sends a
single `contributeWithPermit` transaction. Wallets that cannot sign typed data fall back to the classic
`approve` + `contribute` (two transactions).

## Data stored on-chain

Everything — titles, descriptions, updates, backer messages, profile names and the badge artwork (SVG) —
lives in the contract. There is no backend server; the website is a single static `index.html`.
