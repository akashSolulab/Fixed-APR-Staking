const {expect} = require('chai');
const { ethers, upgrades } = require('hardhat');


describe("Testing fixed staking contract", async () => {

    let Contract;
    let contract;
    let rewardERC20Token;
    let stakedStableCoin;
    const chainlinkAggregatorAddress = "0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF";
    const stakingEndTimestamp = 31536000;

    async function deployRewardERC20Token () {
        const RewardContract = await ethers.getContractFactory("RewardERC20Token")
        const rewardContract = await RewardContract.deploy();
        return rewardContract;
    }

    async function deployStakedStableCoin() {
        const StableCoinContract = await ethers.getContractFactory("RewardERC20Token")
        const stableCoinContract = await StableCoinContract.deploy();
        return stableCoinContract;
    }

    before("Deploying proxy smartcontract", async function() {

        const [owner] = await ethers.getSigners();

        rewardERC20Token = await deployRewardERC20Token();
        stakedStableCoin = await deployStakedStableCoin();

        Contract = await ethers.getContractFactory('StableCoinStaking');

        contract = await upgrades.deployProxy(Contract, [
            rewardERC20Token.address,
            stakedStableCoin.address,
            chainlinkAggregatorAddress,
            stakingEndTimestamp
        ], {kind: 'uups'});
    })

    describe("Deposit stable coins in pool", async function() {
        
        let contractBalanceBeforeDeposit;
        let amountToDeposit;

        before("Deposit tokens to staking contract", async function() {
            const [owner] = await ethers.getSigners();
            await stakedStableCoin.approve(contract.address, ethers.utils.parseEther('100000000000000000000000'));

            amountToDeposit = ethers.utils.parseEther('90');
            contractBalanceBeforeDeposit = await contract.totalStakedInPool();
            await contract.depositInPool(amountToDeposit);
        })

        it("Confirm deposit successful", async () => {
            const [owner] = await ethers.getSigners();
            let contractBalanceAfterDeposit = contractBalanceBeforeDeposit + amountToDeposit;
            expect(await contract.totalStakedInPool()).to.equal(contractBalanceAfterDeposit);
        })

        it("Check user's staked amount updated", async () => {
            const [owner] = await ethers.getSigners();
            let userInfo = await contract.userInfo(owner.address);
            let userStakedAmount = Math.trunc(ethers.utils.formatEther(`${userInfo.amountStaked}`))
            expect(userStakedAmount).to.equal(Math.trunc(ethers.utils.formatEther(String(amountToDeposit))))
        })
    })

    describe("Claim earned rewards and withdraw stable coin", async () => {
        /**
         * Here, For testing
         * 365 days are converted in 365 minutes
         * 365 minutes are converted in 365 seconds
         * 1 month -> 30 sec
         * 6 months -> 180 sec
         * 1 year -> 365 sec
         */
        before("Transfer reward tokens to staking contract", async () => {
            const [owner] = await ethers.getSigners();
            await rewardERC20Token.transfer(contract.address, ethers.utils.parseEther('1000000000000000000000000000'));
            // wait for 30 sec
            function waitForTx(ms) {
                return new Promise((res) => {
                    setTimeout(res, ms);
                });
            }
            await waitForTx(30000).then(async () => {
                const tx = await contract.claimERC20RewardTokens();
                await tx.wait();
            })
        })

        it("Claim rewards within 1 month", async () => {
            const [owner] = await ethers.getSigners();
            let userInfo = await contract.userInfo(owner.address);
            let pendingReward = Number(((userInfo.amountStaked)*30)/(31536000)/1e4);
            expect(parseFloat(userInfo.rewardEarned)).to.be.above(pendingReward);
        })

        it("Withdraw stable coin from pool", async () => {
            const [owner] = await ethers.getSigners();
            let userStablecoinBalanceBeforeWithdrawl = await stakedStableCoin.balanceOf(owner.address);
            let amountToWithdraw = ethers.utils.parseEther('90')
            await contract.withdrawFromPool(amountToWithdraw);
            let userStablecoinBalanceAfterWithdrawl = await stakedStableCoin.balanceOf(owner.address);
            let expectedStablecoinBalance = parseInt((userStablecoinBalanceBeforeWithdrawl)) + parseInt(amountToWithdraw);
            // console.log({"before bal": userStablecoinBalanceBeforeWithdrawl, "expected": expectedStablecoinBalance});
            expect(parseInt((userStablecoinBalanceAfterWithdrawl))).to.equal(expectedStablecoinBalance);
        })
    }) 

    describe("Claim rewards with extra APR based on staking duration", async () => {
        /**
         * Here, For testing
         * 365 days are converted in 365 minutes
         * 365 minutes are converted in 365 seconds
         * 1 month -> 30 sec
         * 6 months -> 180 sec
         * 1 year -> 365 sec
         */

        let userStablecoinBalanceBeforeWithdrawl;
        let amountToDeposit;
        before("Transfer reward tokens to staking contract and deposit stable coin", async () => {
            const [owner] = await ethers.getSigners();

            amountToDeposit = ethers.utils.parseEther('90');
            await contract.depositInPool(amountToDeposit);

            await rewardERC20Token.transfer(contract.address, ethers.utils.parseEther('100000000000000000000000'));
            // wait for 90 sec
            function waitForTx(ms) {
                return new Promise((res) => {
                    setTimeout(res, ms);
                });
            }
            await waitForTx(90000).then(async () => {
                userStablecoinBalanceBeforeWithdrawl = await stakedStableCoin.balanceOf(owner.address);
                const tx = await contract.withdrawFromPool(amountToDeposit);
                await tx.wait();
            })
        })

        it("Claim rewards After 2 month", async () => {
            const [owner] = await ethers.getSigners();
            let userInfo = await contract.userInfo(owner.address);
            let pendingReward = Number(((userInfo.amountStaked)*(500)*90)/(31536000)/1e4);
            expect(parseFloat(userInfo.rewardEarned)).to.be.above(pendingReward);
        })

        it("Withdraw stable coin from pool", async () => {
            const [owner] = await ethers.getSigners();
            let userStablecoinBalanceAfterWithdrawl = await stakedStableCoin.balanceOf(owner.address);
            let expectedStablecoinBalance = parseInt((userStablecoinBalanceBeforeWithdrawl)) + parseInt(amountToDeposit);
            expect(parseInt((userStablecoinBalanceAfterWithdrawl))).to.equal(expectedStablecoinBalance);
        })
    })

    describe("Claim perks with extra APR based on amount staked", async () => {
        /**
         * Here, For testing
         * 365 days are converted in 365 minutes
         * 365 minutes are converted in 365 seconds
         * 1 month -> 30 sec
         * 6 months -> 180 sec
         * 1 year -> 365 sec
         */

        let userStablecoinBalanceBeforeWithdrawl;
        let userStablecoinBalanceAfterWithdrawl;
        let amountToDeposit;
        before("Deposit reward tokens to staking contract and deposit stable coin", async () => {
            const [owner] = await ethers.getSigners();

            amountToDeposit = ethers.utils.parseEther('150');
            await contract.depositInPool(amountToDeposit);

            await rewardERC20Token.transfer(contract.address, ethers.utils.parseEther('1000000000000000000000000'));
            // wait
            function waitForTx(ms) {
                return new Promise((res) => {
                    setTimeout(res, ms);
                });
            }
            await waitForTx(90000).then(async () => {
                userStablecoinBalanceBeforeWithdrawl = await stakedStableCoin.balanceOf(owner.address);
                const tx = await contract.withdrawFromPool(amountToDeposit);
                await tx.wait();
            })
        })

        it("Claim rewards with extra 2% for staking more than $100", async () => {
            const [owner] = await ethers.getSigners();
            let userInfo = await contract.userInfo(owner.address);
            let pendingReward = Number(((userInfo.amountStaked)*(200)*(300)*90)/(31536000)/1e4);
            expect(parseFloat(userInfo.rewardEarned)).to.be.above(pendingReward);
        })

        it("Withdraw stable coin from pool", async () => {
            const [owner] = await ethers.getSigners();
            userStablecoinBalanceAfterWithdrawl = await stakedStableCoin.balanceOf(owner.address);
            let expectedStablecoinBalance = parseInt((userStablecoinBalanceBeforeWithdrawl)) + parseInt(amountToDeposit);
            expect(parseInt(userStablecoinBalanceAfterWithdrawl)).to.equal(expectedStablecoinBalance);
        })
    })

})