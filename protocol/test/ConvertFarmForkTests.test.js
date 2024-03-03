const { expect } = require('chai');
const { deploy } = require('../scripts/deploy.js')
const { EXTERNAL, INTERNAL, INTERNAL_EXTERNAL, INTERNAL_TOLERANT } = require('./utils/balances.js')
const {
  BEAN,
  THREE_CURVE,
  THREE_POOL,
  BEAN_3_CURVE,
  PIPELINE,
  WETH,
  BEAN_ETH_WELL,
  BEANSTALK,
  TRI_CRYPTO_POOL,
  USDT
} = require("./utils/constants");
const { ConvertEncoder } = require('./utils/encoder.js')
const { to18, toBean, toStalk, to6 } = require('./utils/helpers.js')
const { takeSnapshot, revertToSnapshot } = require("./utils/snapshot");
let user, user2, owner;
let userAddress, ownerAddress, user2Address;
const { toBN, encodeAdvancedData, signSiloDepositTokenPermit, signSiloDepositTokensPermit, signTokenPermit } = require('../utils/index.js');
const { deployWell, setReserves, whitelistWell, deployMockBeanEthWell, impersonateBeanEthWell } = require('../utils/well.js');
const { setEthUsdPrice, setEthUsdcPrice, setEthUsdtPrice } = require('../scripts/usdOracle.js');
const fs = require('fs');
const { upgradeWithNewFacets } = require("../scripts/diamond");
const { impersonateBeanstalkOwner, impersonateSigner } = require('../utils/signer.js')
const {
  initContracts,
  draftConvertBeanEthWellToUDSTViaCurveTricryptoThenToBeanVia3Crv,
  curveABI,
  draftConvertBeanEthWellToUDSCViaUniswapThenToBeanVia3Crv
} = require("./utils/pipelineconvert.js");
const { deployBasin } = require("../scripts/basin.js");
const { deployPipeline, impersonatePipeline } = require('../scripts/pipeline.js');
const { getBeanstalk } = require('../utils/contracts.js');

//to get trace with hardhat tracer:
//yarn hardhat test test/ConvertFarm.test.js --trace
//if it errors out, need to run: `export NODE_OPTIONS="--max_old_space_size=32768"` or even higher than that

//attach node debugger:
//node --inspect-brk --unhandled-rejections=strict node_modules/.bin/hardhat test test/ConvertFarmForkTests.test.js --no-compile


describe('Farm Convert', function () {
  before(async function () {
    //I wanted to put this in the same file as ConvertFarm.test.js, but when I tried to refactor
    //some setup code into different functions, this.whatever was not passed through successfully,
    //and I couldn't figure out a clean fix that didn't require a lot of refactoring. Maybe a
    //chai/mocha expert would know better, ChatGPT, Phind and Gemini weren't of much help.
    try {
      await network.provider.request({
        method: "hardhat_reset",
        params: [
          {
            forking: {
              jsonRpcUrl: process.env.FORKING_RPC,
              blockNumber: 19021700
            },
          },
        ],
      });
    } catch(error) {
      console.log('forking error in Silo V3: Grown Stalk Per Bdv:');
      console.log(error);
      return
    }

    [owner, user, user2] = await ethers.getSigners();
    userAddress = user.address;
    user2Address = user2.address;
    // const contracts = await deploy("Test", false, true);

    // upgrade beanstalk with convert and mockAdminFacet:
    const beanstalkOwner = await impersonateBeanstalkOwner();
    await upgradeWithNewFacets({
      diamondAddress: BEANSTALK,
      facetNames: ['ConvertFacet', 'MockAdminFacet'],
      initFacetName: "InitTractor",
      libraryNames: [ 'LibConvert' ],
      facetLibraries: {
        'ConvertFacet': [ 'LibConvert' ]
      },
      bip: false,
      object: false,
      verbose: false,
      account: beanstalkOwner
    });

    
    // ownerAddress = contracts.account;
    // this.diamond = contracts.beanstalkDiamond
    ownerAddress = beanstalkOwner.address;
    this.beanstalk = await getBeanstalk(BEANSTALK);
    impersonateBeanEthWell();
    this.well = await ethers.getContractAt("IWell", BEAN_ETH_WELL);
    this.fakeWell = await deployWell([BEAN, WETH]);
    this.wellToken = await ethers.getContractAt("IERC20", this.well.address)
    this.convert = await ethers.getContractAt("MockConvertFacet", BEANSTALK)
    this.admin = await ethers.getContractAt("MockAdminFacet", BEANSTALK)
    this.bean = await ethers.getContractAt("MockToken", BEAN);
    this.usdt = await ethers.getContractAt("MockToken", USDT);
    this.weth = await ethers.getContractAt("MockToken", WETH);
    this.season = await ethers.getContractAt('MockSeasonFacet', BEANSTALK);
    this.curveTricryptoPool = await ethers.getContractAt(curveABI, TRI_CRYPTO_POOL);
    this.curveBean3crvPool = await ethers.getContractAt(curveABI, BEAN_3_CURVE);
    await this.admin.mintBeans(ownerAddress, to18('1000000000'))
    await this.wellToken.connect(owner).approve(this.beanstalk.address, ethers.constants.MaxUint256)
    await this.bean.connect(owner).approve(this.beanstalk.address, ethers.constants.MaxUint256)

    // await setEthUsdPrice('999.998018')
    // await setEthUsdcPrice('1000')
    // await setEthUsdtPrice('1000')

    // await setReserves(
    //   owner,
    //   this.well,
    //   [to6('1000000'), to18('1000')]
    // );

    // await setReserves(
    //   owner,
    //   this.well,
    //   [to6('1000000'), to18('1000')]
    // );
    // await whitelistWell(this.well.address, '10000', to6('4'))
    // await this.season.captureWellE(this.well.address); //inits well oracle price


    this.silo = await ethers.getContractAt('SiloFacet', BEANSTALK);
    this.farmFacet = await ethers.getContractAt("FarmFacet", BEANSTALK);


    await this.admin.mintBeans(userAddress, toBean('1000000000'));
    await this.admin.mintBeans(user2Address, toBean('1000000000'));

    // const beanstalkOwner = await impersonateBeanstalkOwner();
    // await upgradeWithNewFacets({
    //   diamondAddress: BEANSTALK,
    //   facetNames: ['ConvertFacet'],
    //   libraryNames: [ 'LibConvert' ],
    //   facetLibraries: {
    //     'ConvertFacet': [ 'LibConvert' ]
    //   },
    //   bip: false,
    //   object: false,
    //   verbose: false,
    //   account: beanstalkOwner
    // });

    this.pipeline = await impersonatePipeline();

    await initContracts(); //deploys drafter contract


    await this.bean.connect(user).approve(this.well.address, ethers.constants.MaxUint256);
    await this.bean.connect(user).approve(this.silo.address, ethers.constants.MaxUint256);
    await this.usdt.connect(user).approve(this.curveBean3crvPool.address, ethers.constants.MaxUint256);
    await this.weth.connect(user).approve(this.curveTricryptoPool.address, ethers.constants.MaxUint256);
    await this.wellToken.connect(user).approve(this.pipeline.address, ethers.constants.MaxUint256)
    await this.wellToken.connect(user).approve(this.silo.address, ethers.constants.MaxUint256)
  });


    //uses curve/uniswap/etc
  describe('on-chain convert tests', async function () {

    before(async function () {

    });

    function getBdvFromAddDepositReceipt(silo, siloReceipt) {
      var depositedBdv = 0;
      for (const log of siloReceipt.logs) {
        try {
          const parsedEvent = silo.interface.parseLog(log);
          if (parsedEvent.name == 'AddDeposit') {
            depositedBdv = parsedEvent.args.bdv;
          }
        } catch (e) {
          //for some reason it fails to parse one of the events, 
          console.log('error parsing event: ', e);
        }
      }
      return depositedBdv;
    }


    //test that does a tricrypto and 3crv swap
    it('does a tricrypto and 3crv swap', async function () {

      //first deposit 200 bean into bean:eth well
      await this.bean.connect(user).approve(this.well.address, ethers.constants.MaxUint256);
      //get amount out that we should recieve for depositing 200 beans
      const wellAmountOut = await this.well.getAddLiquidityOut([toBean('200'), to18("0")]);

      await this.well.connect(user).addLiquidity([toBean('200'), to18("0")], ethers.constants.Zero, user.address, ethers.constants.MaxUint256);

      // if we removed that well amount, how many bean would we expect to get?
      const beanAmountOut = await this.well.getRemoveLiquidityOneTokenOut(wellAmountOut, BEAN);

      // deposit the bean:eth
      const siloResult = await this.silo.connect(user).deposit(this.well.address, wellAmountOut, EXTERNAL);

      // get event logs and see how much the actual bdv was
      const siloReceipt = await siloResult.wait();
      const depositedBdv = getBdvFromAddDepositReceipt(this.silo, siloReceipt);
      const stemTip = await this.silo.stemTipForToken(this.well.address);
      let advancedFarmCalls = await draftConvertBeanEthWellToUDSTViaCurveTricryptoThenToBeanVia3Crv(wellAmountOut, 0);
      const farmData = this.farmFacet.interface.encodeFunctionData("advancedFarm", [
        advancedFarmCalls
      ]);


      this.result = await this.convert.connect(user).pipelineConvert(this.well.address, [stemTip], [wellAmountOut], wellAmountOut, this.bean.address, farmData);

      // verify events
      // await expect(this.result).to.emit(this.convert, 'Convert').withArgs(user.address, this.well.address, this.bean.address, wellAmountOut, beanAmountOut);
      await expect(this.result).to.emit(this.silo, 'RemoveDeposits').withArgs(user.address, this.well.address, [stemTip], [wellAmountOut], wellAmountOut, [depositedBdv]);
      // await expect(this.result).to.emit(this.silo, 'AddDeposit').withArgs(user.address, this.bean.address, stemTip, beanAmountOut, beanAmountOut);
    });

    it.only('does a uniswap and 3crv swap', async function () {

      //first deposit 200 bean into bean:eth well
      await this.bean.connect(user).approve(this.well.address, ethers.constants.MaxUint256);
      //get amount out that we should recieve for depositing 200 beans
      const wellAmountOut = await this.well.getAddLiquidityOut([toBean('200'), to18("0")]);

      await this.well.connect(user).addLiquidity([toBean('200'), to18("0")], ethers.constants.Zero, user.address, ethers.constants.MaxUint256);

      // if we removed that well amount, how many bean would we expect to get?
      const beanAmountOut = await this.well.getRemoveLiquidityOneTokenOut(wellAmountOut, BEAN);

      // deposit the bean:eth
      const siloResult = await this.silo.connect(user).deposit(this.well.address, wellAmountOut, EXTERNAL);

      // get event logs and see how much the actual bdv was
      const siloReceipt = await siloResult.wait();
      const depositedBdv = getBdvFromAddDepositReceipt(this.silo, siloReceipt);
      const stemTip = await this.silo.stemTipForToken(this.well.address);
      let advancedFarmCalls = await draftConvertBeanEthWellToUDSCViaUniswapThenToBeanVia3Crv(wellAmountOut, 0);
      const farmData = this.farmFacet.interface.encodeFunctionData("advancedFarm", [
        advancedFarmCalls
      ]);


      this.result = await this.convert.connect(user).pipelineConvert(this.well.address, [stemTip], [wellAmountOut], wellAmountOut, this.bean.address, farmData);

      // verify events
      // await expect(this.result).to.emit(this.convert, 'Convert').withArgs(user.address, this.well.address, this.bean.address, wellAmountOut, beanAmountOut);
      await expect(this.result).to.emit(this.silo, 'RemoveDeposits').withArgs(user.address, this.well.address, [stemTip], [wellAmountOut], wellAmountOut, [depositedBdv]);
      // await expect(this.result).to.emit(this.silo, 'AddDeposit').withArgs(user.address, this.bean.address, stemTip, beanAmountOut, beanAmountOut);
    });
  });
});
