# Admin panel

The owner (the wallet that deployed the contract) sees an **Admin** button in the top bar.

| Action | Function | Notes |
|---|---|---|
| Change fee | `setFee(bps)` | basis points, max 500 (5%). Applies to future claims. |
| Limits | `setLimits(minGoal, maxDays)` | minimum goal in USDC (6 decimals), max duration ≤ 365 days |
| Stop a campaign | `adminCancel(id)` | for scams/abuse — backers can refund 100% |
| Pause | `setPaused(bool)` | blocks new campaigns and contributions; refunds and claims keep working |
| New owner | `transferOwnership(addr)` | fees go to the owner address at claim time |

Fees are transferred to the owner **immediately** when a creator calls `claim()` — there is nothing to withdraw.
Reports (`report(id, reason)`) are emitted as events and counted on the campaign so the owner can review them.
