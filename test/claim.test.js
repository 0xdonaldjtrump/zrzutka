const { setup, assert, reverts, USD } = require("./helpers");
module.exports = async () => {
  console.log("Claim (goal reached) + 1% fee");
  const { signers: [o, a, b, c], z, create, give, bal, time, DAY } = await setup();
  const id = await create(a, 100, 10);
  await give(b, id, 60);
  await reverts(z.connect(a).claim.staticCall(id), "GoalNotReached", "cannot claim below goal");
  await give(c, id, 50);
  await reverts(z.connect(b).claim.staticCall(id), "NotCreator", "only creator claims");
  const a0 = await bal(await a.getAddress()), o0 = await bal(await o.getAddress());
  await (await z.connect(a).claim(id)).wait();
  assert((await bal(await a.getAddress())) - a0 === USD(108.9), "creator gets 99% (108.90 of 110)");
  assert((await bal(await o.getAddress())) - o0 === USD(1.1), "owner gets 1% fee");
  const k = await z.getCampaign(id);
  assert(k.status === 1n && k.goalReachedEarly, "status Claimed, closed early");
  await reverts(z.connect(a).claim.staticCall(id), "NotActive", "cannot claim twice");
  await reverts(z.connect(b).contribute.staticCall(id, USD(1), ""), "NotActive", "no contributions after claim");
  await reverts(z.connect(b).refund.staticCall(id), "NotEligible", "no refunds for successful campaign");
  // claim after deadline also works
  const id2 = await create(a, 10, 2);
  await give(b, id2, 10);
  await time(3 * DAY);
  await (await z.connect(a).claim(id2)).wait();
  assert((await z.getCampaign(id2)).status === 1n, "claim after deadline when goal met");
  const [, raised, fees] = await z.stats();
  assert(raised === USD(120) && fees === USD(1.2), "global stats");
};
