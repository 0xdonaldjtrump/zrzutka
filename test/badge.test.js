const { setup, assert, reverts, USD } = require("./helpers");
module.exports = async () => {
  console.log("Supporter badges (soulbound NFT)");
  const { signers: [, a, b, c], z, create, give } = await setup();
  const id = await create(a, 20, 5, 'Nowy "dach" <szkoły>');
  await give(b, id, 20);
  await reverts(z.connect(b).mintBadge.staticCall(id), "NotEligible", "no badge before success");
  await (await z.connect(a).claim(id)).wait();
  await reverts(z.connect(c).mintBadge.staticCall(id), "NotEligible", "non-backers get no badge");
  await (await z.connect(b).mintBadge(id)).wait();
  await reverts(z.connect(b).mintBadge.staticCall(id), "AlreadyDone", "one badge per campaign");
  const B = await b.getAddress(), tokenId = await z.badgeOf(id, B);
  assert((await z.ownerOf(tokenId)) === B && (await z.balanceOf(B)) === 1n, "badge owned by backer");
  await reverts(z.connect(b).transferFrom.staticCall(B, await c.getAddress(), tokenId), "Soulbound", "badge cannot be transferred");
  const uri = await z.tokenURI(tokenId);
  const json = JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString());
  const svg = Buffer.from(json.image.split(",")[1], "base64").toString();
  assert(json.name === "Zrzutka Supporter #1" && svg.startsWith("<svg") && !svg.includes("<szko"), "on-chain JSON + SVG metadata (title escaped)");
};
