const { upgradeWithNewFacets } = require("../scripts/diamond.js");
const { deployContract } = require("../scripts/contracts");
const fs = require("fs");
const { retryOperation } = require("../utils/read.js");
async function reseedGlobal(account, L2Beanstalk, mock) {
  console.log("-----------------------------------");
  console.log("reseedGlobal: reseedGlobal.\n");

  // Files
  let globalsPath = "./reseed/data/global.json";
  let settings = JSON.parse(await fs.readFileSync(globalsPath));

  await retryOperation(async () => {
    await upgradeWithNewFacets({
      diamondAddress: L2Beanstalk,
      facetNames: [],
      initFacetName: "ReseedGlobal",
      initArgs: [settings],
      bip: false,
      verbose: true,
      account: account
    });
  });
  console.log("-----------------------------------");
}
exports.reseedGlobal = reseedGlobal;
