const { BEAN, BEAN_3_CURVE, STABLE_FACTORY, UNRIPE_BEAN, UNRIPE_LP, WETH, BEANSTALK, BEAN_ETH_WELL } = require('./utils/constants.js');
const { EXTERNAL, INTERNAL, INTERNAL_EXTERNAL, INTERNAL_TOLERANT } = require('./utils/balances.js')
const { impersonateBeanstalkOwner, impersonateSigner } = require('../utils/signer.js');
const { time, mine } = require("@nomicfoundation/hardhat-network-helpers");
const { takeSnapshot, revertToSnapshot } = require("./utils/snapshot.js");
const { setEthUsdcPrice, setEthUsdPrice } = require('../utils/oracle.js');
const { upgradeWithNewFacets } = require("../scripts/diamond");
const { mintEth, mintBeans } = require('../utils/mint.js');
const { getBeanstalk } = require('../utils/contracts.js');
const { ConvertEncoder } = require('./utils/encoder.js');
const { bipSeedGauge } = require('../scripts/bips.js');
const { to6, to18 } = require('./utils/helpers.js');
const { setReserves } = require('../utils/well.js');
const { toBN } = require('../utils/helpers.js');
const { ethers } = require('hardhat');
const { expect } = require('chai');

let user,user2, owner;

let snapshotId


describe('SeedGauge Init Test', function () {
  before(async function () {

    [user, user2] = await ethers.getSigners()
    owner = await impersonateBeanstalkOwner();

    try {
      await network.provider.request({
        method: "hardhat_reset",
        params: [
          {
            forking: {
              jsonRpcUrl: process.env.FORKING_RPC,
              blockNumber: 18696041 //a random semi-recent block close to Grown Stalk Per Bdv pre-deployment
            },
          },
        ],
      });
    } catch(error) {
      console.log('forking error in seed Gauge');
      console.log(error);
      return
    }

    this.beanstalk = await getBeanstalk()
    this.bean = await ethers.getContractAt('BeanstalkERC20', BEAN)

    // seed Gauge
    await bipSeedGauge(true, undefined, false)
  });

  beforeEach(async function () {
    snapshotId = await takeSnapshot()
  });

  afterEach(async function () {
    await revertToSnapshot(snapshotId)
  });

  describe('init state', async function () {

    // TODO: add check once un-migrated bdvs are verified.
    it('totalDepositedBDV', async function () {
      console.log("total deposited BDV")
      console.log("BEAN:", await this.beanstalk.getTotalDepositedBdv(BEAN));
      console.log("Bean3crv:", await this.beanstalk.getTotalDepositedBdv(BEAN_3_CURVE));
      console.log("BeanETH:", await this.beanstalk.getTotalDepositedBdv(BEAN_ETH_WELL));
      console.log("Unripe Bean:", await this.beanstalk.getTotalDepositedBdv(UNRIPE_BEAN));
      console.log("Unripe LP:", await this.beanstalk.getTotalDepositedBdv(UNRIPE_LP));
      
      console.log("amount migrated since BIP-38:")
      console.log("BEAN:", await this.beanstalk.totalMigratedBdv(BEAN));
      console.log("BEAN3CRV:", await this.beanstalk.totalMigratedBdv(BEAN_3_CURVE));
      console.log("BeanETH:", await this.beanstalk.totalMigratedBdv(BEAN_ETH_WELL));
      console.log("Unripe Bean:", await this.beanstalk.totalMigratedBdv(UNRIPE_BEAN));
      console.log("Unripe LP:", await this.beanstalk.totalMigratedBdv(UNRIPE_LP));
    })

    it('average grown stalk per BDV per Season', async function () {
      expect(await this.beanstalk.getAverageGrownStalkPerBdvPerSeason()).to.be.equal(to6('5.324305'));
    })

    it('average Grown Stalk Per BDV', async function() {
      // average is 2.3839 grown stalk per BDV
      // note: should change with updated BDVs
      expect(await this.beanstalk.getAverageGrownStalkPerBdv()).to.be.equal(22858);
    })

    it('totalBDV', async function () {
      // ~40m total BDV
      expect(await this.beanstalk.getTotalBdv()).to.be.within(to6('42000000'), to6('43000000'));
    })

    it('L2SR', async function () {
      // the L2SR may differ during testing, due to the fact 
      // that the L2SR is calculated on twa reserves, and thus may slightly differ due to 
      // timestamp differences.
      expect(await this.beanstalk.getLiquidityToSupplyRatio()).to.be.within(to18('1.01'), to18('1.03'));
    })
    
    it('bean To MaxLPGpRatio', async function () {
      expect(await this.beanstalk.getBeanToMaxLpGpPerBdvRatio()).to.be.equal(to18('33.333333333333333333'));
      expect(await this.beanstalk.getBeanToMaxLpGpPerBdvRatioScaled()).to.be.equal(to18('66.666666666666666666'));
    })

    it('lockedBeans', async function () {
      // ~25.5m locked beans, ~35.8m total beans
      expect(await this.beanstalk.getLockedBeans()).to.be.within(to6('25100000.000000'), to6('25300000.000000'));
    })

    it('usd Liquidity', async function () {
      // ~13.2m usd liquidity in Bean:Eth
      expect(await this.beanstalk.getBeanEthTwaUsdLiquidity()).to.be.within(to18('13200000'), to18('13400000'));
      // ~13.2m usd liquidity in Bean:Eth
      expect(await this.beanstalk.getTotalUsdLiquidity()).to.be.within(to18('13200000'), to18('13400000'));
    })

    it('gaugePoints', async function () {
      expect(await this.beanstalk.getGaugePoints(BEAN_ETH_WELL)).to.be.equal(to18('1000'));
    })
  })

  // verify that bean3crv has properly dewhitelisted.
  describe('bean3crv dewhitelisted', async function () {

    beforeEach(async function () {
      // deploy mockAdminFacet to mint beans.
      await upgradeWithNewFacets({
        diamondAddress: BEANSTALK,
        facetNames: ['MockAdminFacet'],
        bip: false,
        object: false, 
        verbose: false,
        account: owner
    })
      await mintBeans(user.address, to6('1000'))
      await this.bean.connect(user).approve(this.beanstalk.address, to6('1000'))
      await this.beanstalk.connect(user).addLiquidity(
        BEAN_3_CURVE,
        STABLE_FACTORY,
        [to6('1000'), to18('0')],
        to18('0'),
        EXTERNAL,
        INTERNAL
      )
    })

    it('returns correct siloSetting values', async function () {
      const settings = await this.beanstalk.tokenSettings(BEAN_3_CURVE)
      // milestone season, stem, or stalkIssuedPerBDV should not be cleared.
      expect(settings[0]).to.equal('0x00000000') // BDV selector
      expect(settings[1]).to.equal(0) // stalkEarnedPerSeason
      expect(settings[2]).to.equal(10000) // StalkIssuedPerBDV
      expect(settings[3]).to.equal(17653) // milestoneSeason
      expect(settings[4]).to.equal(12089750000) // milestoneStem
      expect(settings[5]).to.equal('0x00') // encodeType
      expect(settings[6]).to.equal(-3250000) // deltaStalkEarnedPerSeason
      expect(settings[7]).to.equal('0x00000000') // gp Selector
      expect(settings[8]).to.equal('0x00000000') // lw Selector
      expect(settings[9]).to.equal(0) // gaugePoints
      expect(settings[10]).to.equal(0) // optimal % deposited BDV
    })

    it('reverts on deposit', async function () {
      await expect(this.beanstalk.connect(user).deposit(BEAN_3_CURVE, to18('100'), INTERNAL))
        .to.be.revertedWith('Silo: Token not whitelisted')
    })

    it('reverts on conversion to bean3crv', async function () {
      // note: convert validates convert payload first.
      await expect(this.beanstalk.connect(user).convert(
        ConvertEncoder.convertBeansToCurveLP(to18('100'), to6('0'), BEAN_3_CURVE), 
        [0], 
        [to18('200')]
      )).to.be.revertedWith("Convert: Invalid payload")
    })

    // mow arbitrary address that contains a bean3crv deposit.
    it('allows legacy bean3crv to be mown', async function () {
      initalStalk = await this.beanstalk.balanceOfStalk(
        '0xb0B822e1c3995503442682CaEea1b6c683169D2e'
      )
      await this.beanstalk.mow(
        '0xb0B822e1c3995503442682CaEea1b6c683169D2e',
        BEAN_3_CURVE
      )
      newStalk = await this.beanstalk.balanceOfStalk(
        '0xb0B822e1c3995503442682CaEea1b6c683169D2e'
      )

      await expect(newStalk).to.be.above(initalStalk)
    })
    
  })

})