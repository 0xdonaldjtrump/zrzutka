const { setup, assert, reverts, USD } = require("./helpers");
module.exports = async () => {
  console.log("Deadline extension");
  const { signers: [, a, b], z, create, give, time, DAY } = await setup();
  const id = await create(a, 100, 5);
  const d0 = (await z.getCampaign(id)).deadline;
  await reverts(z.connect(a).extendDeadline.staticCall(id, 31), "BadInput", "max +30 days");
  await reverts(z.connect(b).extendDeadline.staticCall(id, 5), "NotCreator", "only creator extends");
  await (await z.connect(a).extendDeadline(id, 10)).wait();
  assert((await z.getCampaign(id)).deadline - d0 === BigInt(10 * DAY), "extended by 10 days");
  await reverts(z.connect(a).extendDeadline.staticCall(id, 1), "BadInput", "only one extension");
  const id2 = await create(a, 10, 5);
  await give(b, id2, 10);
  await reverts(z.connect(a).extendDeadline.staticCall(id2, 5), "GoalReached", "no extension once goal reached");
  const id3 = await create(a, 10, 1);
  await time(2 * DAY);
  await reverts(z.connect(a).extendDeadline.staticCall(id3, 5), "Ended", "no extension after deadline");
};
