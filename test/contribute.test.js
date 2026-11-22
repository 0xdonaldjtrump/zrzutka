const { setup, assert, reverts, USD } = require("./helpers");
module.exports = async () => {
  console.log("Contributions (approve + permit)");
  const { signers: [, a, b, c], z, usdc, create, give, permitSig, time, DAY, provider } = await setup();
  const id = await create(a, 100, 7);
  await give(b, id, 30, "Good luck!");
  await give(b, id, 10, "More!");
  await give(c, id, 25, "");
  let k = await z.getCampaign(id);
  assert(k.raised === USD(65) && k.backers === 2n, "raised 65, 2 unique backers");
  assert((await z.contributionOf(id, await b.getAddress())) === USD(40), "contribution per backer adds up");
  const [list, total] = await z.getBackings(id, 0, 10);
  assert(total === 3n && list[0].amount === USD(25) && list[2].message === "Good luck!", "backings list newest first with messages");
  // permit: one transaction, no approve
  const deadline = BigInt((await provider.getBlock("latest")).timestamp + 3600);
  const sig = await permitSig(3, USD(15), deadline);
  await (await z.connect(c).contributeWithPermit(id, USD(15), "via permit", deadline, sig.v, sig.r, sig.s)).wait();
  assert((await z.contributionOf(id, await c.getAddress())) === USD(40), "contribution with permit signature");
  await reverts(z.connect(b).contribute.staticCall(id, 0, ""), "BadInput", "zero amount rejected");
  await reverts(z.connect(b).contribute.staticCall(id, USD(1), "x".repeat(201)), "BadInput", "message max 200 bytes");
  await time(8 * DAY);
  await reverts(z.connect(b).contribute.staticCall(id, USD(1), ""), "Ended", "no contributions after deadline");
  assert((await z.campaignsBackedBy(await b.getAddress())).length === 1, "campaigns backed by user");
};
