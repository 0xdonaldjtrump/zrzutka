const { setup, assert, reverts, USD } = require("./helpers");
module.exports = async () => {
  console.log("Refunds (failed or cancelled)");
  const { signers: [, a, b, c], z, create, give, bal, time, DAY } = await setup();
  const id = await create(a, 100, 5);
  await give(b, id, 30);
  await give(c, id, 20);
  await reverts(z.connect(b).refund.staticCall(id), "NotEligible", "no refund while active");
  await time(6 * DAY);
  const b0 = await bal(await b.getAddress());
  await (await z.connect(b).refund(id)).wait();
  assert((await bal(await b.getAddress())) - b0 === USD(30), "failed campaign: full refund");
  await reverts(z.connect(b).refund.staticCall(id), "NothingToRefund", "no double refund");
  await reverts(z.connect(a).refund.staticCall(id), "NothingToRefund", "non-backer gets nothing");
  await reverts(z.connect(a).claim.staticCall(id), "GoalNotReached", "creator cannot claim failed campaign");
  // cancel
  const id2 = await create(a, 100, 5);
  await give(c, id2, 40);
  await (await z.connect(a).cancel(id2)).wait();
  const c0 = await bal(await c.getAddress());
  await (await z.connect(c).refund(id2)).wait();
  assert((await bal(await c.getAddress())) - c0 === USD(40), "cancelled campaign: refund before deadline");
  assert((await z.getCampaign(id2)).refunded === USD(40), "refunded amount tracked");
};
