const { expect } = require('chai')
const { deploy } = require('../scripts/deploy.js')
const { takeSnapshot, revertToSnapshot } = require("./utils/snapshot")
const { to6, toStalk, toBean, to18 } = require('./utils/helpers.js');
const { USDC, UNRIPE_BEAN, UNRIPE_LP, BEAN, THREE_CURVE, THREE_POOL, BEAN_3_CURVE, BEAN_ETH_WELL, BEANSTALK_PUMP, STABLE_FACTORY } = require('./utils/constants.js');
const { EXTERNAL, INTERNAL } = require('./utils/balances.js');
const { ethers } = require('hardhat');
const { advanceTime } = require('../utils/helpers.js');
const { deployMockWell, whitelistWell, deployMockWellWithMockPump } = require('../utils/well.js');
const { updateGaugeForToken } = require('../utils/gauge.js');
const { setEthUsdPrice, setEthUsdcPrice, setEthUsdtPrice } = require('../scripts/usdOracle.js');
const ZERO_BYTES = ethers.utils.formatBytes32String('0x0')

let user, user2, owner;
let userAddress, ownerAddress, user2Address;

async function setToSecondsAfterHour(seconds = 0) {
  const lastTimestamp = (await ethers.provider.getBlock('latest')).timestamp;
  const hourTimestamp = parseInt(lastTimestamp/3600 + 1) * 3600 + seconds
  await network.provider.send("evm_setNextBlockTimestamp", [hourTimestamp])
}


describe('Gauge', function () {
  before(async function () {
    [owner, user] = await ethers.getSigners()
    userAddress = user.address;
    const contracts = await deploy("Test", false, true)
    ownerAddress = contracts.account;
    this.diamond = contracts.beanstalkDiamond;
    this.silo = await ethers.getContractAt('MockSiloFacet', this.diamond.address)
    this.field = await ethers.getContractAt('MockFieldFacet', this.diamond.address)
    this.season = await ethers.getContractAt('MockSeasonFacet', this.diamond.address)
    this.seasonGetter = await ethers.getContractAt('SeasonGettersFacet', this.diamond.address)
    this.unripe = await ethers.getContractAt('MockUnripeFacet', this.diamond.address)
    this.fertilizer = await ethers.getContractAt('MockFertilizerFacet', this.diamond.address)
    this.curve = await ethers.getContractAt('CurveFacet', this.diamond.address)
    this.bean = await ethers.getContractAt('MockToken', BEAN);

    await this.bean.connect(owner).approve(this.diamond.address, to6('100000000'))
    await this.bean.connect(user).approve(this.diamond.address, to6('100000000'))

    // set balances to bean3crv
    this.threePool = await ethers.getContractAt('Mock3Curve', THREE_POOL);
    this.threeCurve = await ethers.getContractAt('MockToken', THREE_CURVE)
    this.beanThreeCurve = await ethers.getContractAt('MockMeta3Curve', BEAN_3_CURVE);
    await this.threeCurve.mint(userAddress, to18('1000'))
    await this.beanThreeCurve.connect(owner).approve(this.diamond.address, to18('100000000'))
    await this.beanThreeCurve.connect(user).approve(this.diamond.address, to18('100000000'))
    await this.threeCurve.connect(user).approve(this.diamond.address, to18('100000000000'))
    await this.threeCurve.connect(user).approve(this.beanThreeCurve.address, to18('100000000000'))

    // bean3crv set at parity, 1,000,000 on each side.
    await this.beanThreeCurve.set_balances([to6('1000000'), to18('1000000')]);
    await this.beanThreeCurve.set_balances([to6('1000000'), to18('1000000')]);
   
    // init wells
    [this.well, this.wellFunction, this.pump] = await deployMockWellWithMockPump()
    await this.well.connect(owner).approve(this.diamond.address, to18('100000000'))
    await this.well.connect(user).approve(this.diamond.address, to18('100000000'))

    await this.well.setReserves([to6('1000000'), to18('1000')])
    await this.well.mint(ownerAddress, to18('500'))
    await this.well.mint(userAddress, to18('500'))
    await this.season.siloSunrise(0)
    await whitelistWell(this.well.address, '10000', to6('4'));
    await this.season.captureWellE(this.well.address);

    await setEthUsdPrice('999.998018')
    await setEthUsdcPrice('1000')
    await setEthUsdtPrice('1000')

    // add unripe
    this.unripeBean = await ethers.getContractAt('MockToken', UNRIPE_BEAN)
    this.unripeLP = await ethers.getContractAt('MockToken', UNRIPE_LP)
    await this.unripeLP.mint(ownerAddress, to18('10000'))
    await this.unripeBean.mint(ownerAddress, to6('10000'))
    await this.unripeLP.connect(owner).approve(this.diamond.address, to6('100000000'))
    await this.unripeBean.connect(owner).approve(this.diamond.address, to6('100000000'))
    await this.unripe.connect(owner).addUnripeToken(UNRIPE_BEAN, BEAN, ZERO_BYTES)
    await this.unripe.connect(owner).addUnripeToken(UNRIPE_LP, BEAN_ETH_WELL, ZERO_BYTES);

    // update Gauge
    await updateGaugeForToken(BEAN_ETH_WELL, to18('95'))
    await updateGaugeForToken(BEAN_3_CURVE, to18('5'))
  })

  beforeEach(async function () {
    snapshotId = await takeSnapshot()
  })

  afterEach(async function () {
    await revertToSnapshot(snapshotId)
  })

  describe('Bean to maxLP ratio', function () {
    // MockInitDiamond initalizes BeanToMaxLpGpPerBDVRatio to 50% (50e6)

    describe('L2SR > excessively high L2SR % + P > 1', async function () {
      it("increases Bean to maxLP ratio", async function () {
        this.result = await this.season.seedGaugeSunSunrise('0', 108);
        expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatio()).to.be.equal(to18('51'));
        await expect(this.result).to.emit(this.season, 'BeanToMaxLpGpPerBDVRatioChange')
          .withArgs(
            3,     // season
            108,    // caseId
            to18('100'), // relative change (100% of original) 
            to18('1')    // absolute change (-0.5%)
          );
      })
    });

    describe('moderately high L2SR % < L2SR < excessively high L2SR % + P < 1', async function () {
      it("decreases Bean to maxLP ratio", async function () {
        this.result = await this.season.seedGaugeSunSunrise('0', 75);
        expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatio()).to.be.equal(to18('49'));
        await expect(this.result).to.emit(this.season, 'BeanToMaxLpGpPerBDVRatioChange')
          .withArgs(
            3, // season
            75, // caseId
            to18('100'), // relative multiplier 
            to18('-1') // absolute change (-0.25%)
          );
      })
    });

    describe('moderately low L2SR % < L2SR < moderately high L2SR % + P > 1', async function () {
      it("increases Bean to maxLP ratio", async function () {
        this.result = await this.season.seedGaugeSunSunrise('0', 36);
        expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatio()).to.be.equal(to18('55'));
        await expect(this.result).to.emit(this.season, 'BeanToMaxLpGpPerBDVRatioChange')
          .withArgs(
            3, // season
            36, // caseId
            to18('110'), // relative multiplier 
            to18('0') // absolute change (+0.25%)
          );
      })
    });

    describe('L2SR < moderately low L2SR %', async function () {
      it("iincreases Bean to maxLP ratio", async function () {
        this.result = await this.season.seedGaugeSunSunrise('0', 0);
        expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatio()).to.be.equal(to18('55'));
        await expect(this.result).to.emit(this.season, 'BeanToMaxLpGpPerBDVRatioChange')
          .withArgs(
            3, // season
            0, // caseId
            to18('110'), // relative multiplier 
            to18('0') // absolute change (+0.5%)
          );
      })
    });

    it("Bean to maxLP ratio cannot go under 0%", async function () {
      await this.season.setBeanToMaxLpGPperBDVRatio(to18('0.5'));
      this.result = await this.season.seedGaugeSunSunrise('0', 111);
      expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatio()).to.be.equal('0');
      await expect(this.result).to.emit(this.season, 'BeanToMaxLpGpPerBDVRatioChange')
        .withArgs(
          3,     // season
          111,    // caseId
          to18('100'), // relative change (100% of original) 
          to18('-0.5')    // absolute change (-0.4%)
        );
    })

    it("Bean to maxLP ratio cannot go above 100%", async function () {
      await this.season.setBeanToMaxLpGPperBDVRatio(to18('99.9'));
      this.result = await this.season.seedGaugeSunSunrise('0', 0);
      expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatio()).to.be.equal(to18('100'));
      await expect(this.result).to.emit(this.season, 'BeanToMaxLpGpPerBDVRatioChange')
        .withArgs(
          3,     // season
          0,    // caseId
          to18('100'), // relative change (100% of original) 
          to18('0.1')    // absolute change (+0.1%)
        );
    })

    it("Bean to maxLP ratio properly scales", async function () {
      await this.season.setBeanToMaxLpGPperBDVRatio(to18('50'));
      // 1 - (0.50 * (1 - 0.25)) = 0.625
      expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatioScaled()).to.be.equal(to18('62.5'));

      await this.season.setBeanToMaxLpGPperBDVRatio(to18('51'));
     // 1 - (0.51 * (1 - 0.25)) = 0.6175
      expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatioScaled()).to.be.equal(to18('61.75'))
    })    

    it("Bean to maxLP ratio cannot decrease below min %", async function () {
      await this.season.setBeanToMaxLpGPperBDVRatio(to18('100'));
      // 0.25 + 0 * (1 - 0.25) = 0.25
      expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatioScaled()).to.be.equal(to18('25'));
    })

    it("Bean to maxLP ratio cannot exceed max %", async function () {
      await this.season.setBeanToMaxLpGPperBDVRatio(to18('0'));
      // 0.25 + 1 * (1 - 0.25) = 1
      expect(await this.seasonGetter.getBeanToMaxLpGPperBDVRatioScaled()).to.be.equal(to18('100'));
    })

  })

  describe('L2SR calculation', async function () {
    describe("getter", function () {

      it('inital state', async function () {
        // bean:eth has a ratio of 1000:1 (1m beans paired against 1m usd of eth),
        // bean:3crv has a ratio of 1:1 (1m beans paired against 1m usd of 3crv)
        // total supply of bean is 2m, with 0 circulating.
        // total non-bean liquidity is 2m.
        await this.bean.mint(ownerAddress, to6('2000000'));
        expect(
          await this.seasonGetter.getLiquidityToSupplyRatio()
          ).to.be.equal(to18('1'));
      })

      it('returns 0 if no liquidity', async function () {
        await this.bean.mint(ownerAddress, to6('2000000'));
        await this.pump.setInstantaneousReserves([to6('0'), to18('0')])
        await this.beanThreeCurve.set_balances([to6('0'), to18('0')]);
        await this.beanThreeCurve.set_balances([to6('0'), to18('0')]);

        expect(
          await this.seasonGetter.getLiquidityToSupplyRatio()
        ).to.be.equal(0);
      })

      it('returns 0 if no supply', async function () {
        this.beanSupply = await this.bean.totalSupply();
        this.result = await this.seasonGetter.getLiquidityToSupplyRatio();
        await expect(this.beanSupply).to.be.equal(0);
        await expect(this.result).to.be.equal(0);
      }) 

      it('decreases', async function () {
        await this.bean.mint(ownerAddress, to6('2000000'));
        initalL2SR = await this.seasonGetter.getLiquidityToSupplyRatio();
        
        await this.bean.mint(ownerAddress, to6('2000000'));
        newL2SR = await this.seasonGetter.getLiquidityToSupplyRatio();

        expect(newL2SR).to.be.equal(to18('0.5'));
        expect(newL2SR).to.be.lt(initalL2SR);

      })

      it('increases', async function () {
        await this.bean.mint(ownerAddress, to6('2000000'));
        initalL2SR = await this.seasonGetter.getLiquidityToSupplyRatio();

        await this.bean.connect(owner).burn(to6('1000000'));
        newL2SR = await this.seasonGetter.getLiquidityToSupplyRatio();

        expect(newL2SR).to.be.equal(to18('2'));
        expect(newL2SR).to.be.gt(initalL2SR);
      })
    })

    // when beanstalk has outstanding fertilizer (aka unripe assets)
    // a portion of the supply is locked, due to the difference between
    // the underlying amount and redemption price. 
    // thus the supply can be reduced.
    describe('with unripe', function() {
      before(async function() {
        await this.bean.mint(ownerAddress, to6('2000000'));
        // enable fertilizer, 10000 sprouts unfertilized
        await this.fertilizer.setFertilizerE(true, to6('10000'))
        await this.unripe.connect(owner).addUnderlying(
          UNRIPE_BEAN,
          to6('1000')
        )

        await this.unripe.connect(owner).addUnderlying(
          UNRIPE_LP,
          to18('1')
        )

        // add 1000 LP to 10,000 unripe
        await this.fertilizer.connect(owner).setPenaltyParams(to6('100'), to6('1000'))
      })

      it('getters', async function () {
        // urBean supply * 10% recapitalization (underlyingBean/UrBean) * 10% (fertilizerIndex/totalFertilizer)
        // = 10000 urBEAN * 10% = 1000 BEAN * (100-10%) = 900 beans locked.
        // urBEANETH supply * 0.1% recapitalization (underlyingBEANETH/UrBEANETH) * 10% (fertilizerIndex/totalFertilizer)
        // = 10000 urBEANETH * 0.1% = 1 BEANETH * (100-10%) = .9 BEANETHLP locked.
        // 1m beans underlay 1000 beanETHLP tokens.
        // .9/1000 * 1m = 900 beans locked.
        expect(await this.unripe.getLockedBeansInUrBEAN()).to.be.eq(to6('900'));
        expect(await this.unripe.getLockedBeansInUrBEANETH()).to.be.eq(to6('900'));
        expect(await this.unripe.getLockedBeans()).to.be.eq(to6('1800'));
        expect(
          await this.seasonGetter.getLiquidityToSupplyRatio()
          ).to.be.eq(to18('1.000900810729656691'));
      })
    })
  })

  describe('GaugePoints', async function () {
    beforeEach(async function () {
      beanETHGaugePoints = await this.seasonGetter.getGaugePoints(BEAN_ETH_WELL)
      bean3crvGaugePoints = await this.seasonGetter.getGaugePoints(BEAN_3_CURVE)
      // deposit half beanETH, half bean3crv:
      await this.silo.connect(user).deposit(BEAN_ETH_WELL, to18('1'), EXTERNAL);
      await this.bean.mint(userAddress, to6('10000'))
      await this.curve.connect(user).addLiquidity(
        BEAN_3_CURVE,
        STABLE_FACTORY,
        [to6('1000'), to18('1000')],
        to18('2000'),
        EXTERNAL,
        EXTERNAL
      );
      await this.silo.connect(user).deposit(BEAN_3_CURVE, to18('63.245537'), EXTERNAL);
      // deposit beans: 
      await this.silo.connect(user).deposit(BEAN, to6('100'), EXTERNAL);
      this.result = (await this.season.mockStepGauge());
    })

    it('updates gauge points', async function () {
      expect(await this.seasonGetter.getGaugePoints(BEAN_ETH_WELL)).to.be.eq(to18('96'));
      expect(await this.seasonGetter.getGaugePoints(BEAN_3_CURVE)).to.be.eq(to18('4'));
    })

    it('update seeds values', async function () {
      // mockInitDiamond sets s.averageGrownStalkPerBdvPerSeason to 10e6 (avg 10 seeds per BDV),
      // and BeanToMaxLpGpPerBDVRatio to 50% (BeanToMaxLpGpPerBDVRatioScaled = 0.625)
      // total BDV of ~226.5 (100 + 63.245537 + 63.245537)
      // 1 seed = 1/10000 stalk, so 2265/10000 stalk should be issued this season.
      // BEANETHGP = 96, gpPerBDV = 96/63.245537 = 1.51789
      // BEAN3CRV = 4, gpPerBDV = 4/63.245537 = 0.0632455 
      // BEANgpPerBDV = 0.625 * 1.51789 = 0.948681
      // total GP = 100 + (0.948681*100) = 194.861
      // stalkPerGp = 2264910730 / 194.861 = 11_622_773/1e10 stalk per GP
      // stalkPerGp * GpPerBDV = stalkIssuedPerBDV
      // stalkIssuedPerBeanBDV =  11_622_773/1e10 * 0.948683 = ~11_026_327/1e10
      // stalkIssuedPerBeanETH = 11_622_773/1e10 * 1.51789 = ~17_642_090/1e10
      // stalkIssuedPerBean3CRV = 11_622_773/1e10 * 0.0632455 = ~735088/1e10
      expect((await this.silo.tokenSettings(BEAN))[1]).to.be.eq(11026333);
      expect((await this.silo.tokenSettings(BEAN_ETH_WELL))[1]).to.be.eq(17642133);
      expect((await this.silo.tokenSettings(BEAN_3_CURVE))[1]).to.be.eq(735088);
    })
    
    it('emits events', async function () {
      await expect(this.result).to.emit(this.season, 'GaugePointChange').withArgs(
        2,  // season
        BEAN_ETH_WELL,  // token
        to18('96') // new gauge points
      );
      await expect(this.result).to.emit(this.season, 'GaugePointChange').withArgs(
        2,  // season
        BEAN_3_CURVE,  // token
        to18('4') // new gauge points
      );
    })

  })

  describe('averageGrownStalkPerBdvPerSeason', async function () {
    before(async function() {
      await this.season.mockSetAverageGrownStalkPerBdvPerSeason(to6('0'));
      await this.bean.mint(userAddress, to6('2000'));
      this.result = await this.silo.connect(user).deposit(this.bean.address, to6('1000'), EXTERNAL)
    })
    it('getter', async function (){
      expect(await this.seasonGetter.getAverageGrownStalkPerBdvPerSeason()).to.be.equal(to6('0'));
      expect(await this.seasonGetter.getNewAverageGrownStalkPerBdvPerSeason()).to.be.equal(to6('0'));
    })

    it('increases after some seasons pass', async function () {
      await this.season.teleportSunrise(4322)
      // season 4322 (user does not gain any stalk until season 2)
      await this.silo.mow(userAddress, this.bean.address)
      expect(await this.seasonGetter.getAverageGrownStalkPerBdvPerSeason()).to.be.equal(0);
      expect(await this.seasonGetter.getNewAverageGrownStalkPerBdvPerSeason()).to.be.equal(to6('2'));
      await this.seasonGetter.updateStalkPerBdvPerSeason();
      expect(await this.seasonGetter.getAverageGrownStalkPerBdvPerSeason()).to.be.equal(to6('2'));
    })

    it('decreases after a new deposit', async function() {
      await this.season.teleportSunrise(4322)
      await this.silo.mow(userAddress, this.bean.address)
      await this.seasonGetter.updateStalkPerBdvPerSeason();
      expect(await this.seasonGetter.getAverageGrownStalkPerBdvPerSeason()).to.be.equal(to6('2'));
      this.result = await this.silo.connect(user).deposit(this.bean.address, to6('1000'), EXTERNAL)
      expect(await this.seasonGetter.getNewAverageGrownStalkPerBdvPerSeason()).to.be.equal(to6('1'));
    })

    it('updates averageGrownStalkPerBDVPerSeason if a week has elapsed', async function () {
      expect(await this.seasonGetter.getAverageGrownStalkPerBdvPerSeason()).to.be.equal(to6('0'));
      // deposit half beanETH, half bean3crv:
      await this.silo.connect(user).deposit(BEAN_ETH_WELL, to18('1'), EXTERNAL);
      await this.bean.mint(userAddress, to6('10000'))
      await this.curve.connect(user).addLiquidity(
        BEAN_3_CURVE,
        STABLE_FACTORY,
        [to6('1000'), to18('1000')],
        to18('2000'),
        EXTERNAL,
        EXTERNAL
      );
      await this.silo.connect(user).deposit(BEAN_3_CURVE, to18('63.245537'), EXTERNAL);
      // deposit beans: 
      await this.silo.connect(user).deposit(BEAN, to6('100'), EXTERNAL);
      await this.season.teleportSunrise(168);
      await this.silo.mow(userAddress, this.bean.address)
      await this.silo.mow(userAddress, BEAN_ETH_WELL)
      await this.silo.mow(userAddress, BEAN_3_CURVE)
      await this.season.mockStepGauge();

      expect(await this.seasonGetter.getAverageGrownStalkPerBdvPerSeason()).to.be.equal(84722);
    });
  })
  
})