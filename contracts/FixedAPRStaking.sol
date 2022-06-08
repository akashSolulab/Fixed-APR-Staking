//SPDX-License-Identifier: Undefined

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract StableCoinStaking is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint public stakingEndBlock;

    uint public totalStakedInPool;

    EnumerableSet.AddressSet private stakeHoldersList;

    IERC20Upgradeable public rewardERC20Token;
    IERC20Upgradeable public stakedStableCoin;
    AggregatorV3Interface public chainlinkAggregatorAddress; // 0x777A68032a88E5A84678A77Af2CD65A7b3c0775a - rinkeby

    struct UserInfo {
        uint amountStaked;
        uint depositDuration;
        uint rewardEarned;
        uint lastRewardWithdrawl;
    }

    mapping(uint => uint) public rewardRates;
    mapping(uint => uint) public bonusRewardRates;
    mapping(address => UserInfo) public userInfo;

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function initialize (
        IERC20Upgradeable _rewardERC20Token,
        IERC20Upgradeable _stakedStableCoin,
        AggregatorV3Interface _chainlinkAggregatorAddress,
        uint _stakingEndBlock
    ) external initializer {
        rewardERC20Token = _rewardERC20Token;
        stakedStableCoin = _stakedStableCoin;
        chainlinkAggregatorAddress = _chainlinkAggregatorAddress;
        stakingEndBlock = _stakingEndBlock;
        _setRewardRates();
        _setBonusRewardRates();
    }

    function depositInPool (uint _amount) external {
        require(_amount > 0, "depositStableCoin:: amount should be greater than zero");

        IERC20Upgradeable(stakedStableCoin).transferFrom(msg.sender, address(this), _amount);

        _updateUserInfo();
        
        userInfo[msg.sender].amountStaked = userInfo[msg.sender].amountStaked.add(_amount);

        totalStakedInPool = totalStakedInPool.add(_amount);

        if(!stakeHoldersList.contains(msg.sender)) {
            stakeHoldersList.add(msg.sender);
        }
    }

    function withdrawFromPool(uint _amount) external {
        require(_amount <= userInfo[msg.sender].amountStaked, "withdrawFromPool:: can not withdraw more than your staked amount");

        _updateUserInfo();

        IERC20Upgradeable(stakedStableCoin).transferFrom(address(this), msg.sender, _amount);

        userInfo[msg.sender].amountStaked = userInfo[msg.sender].amountStaked.sub(_amount);

        totalStakedInPool = totalStakedInPool.sub(_amount);

        if(stakeHoldersList.contains(msg.sender)) {
            stakeHoldersList.remove(msg.sender);
        }
    }

    function claimERC20RewardTokens() external {
        _updateUserInfo();
    }

    function _setRewardRates() internal {
        rewardRates[0] = 500;
        rewardRates[1] = 1000;
        rewardRates[2] = 1500;
    }

    function _setBonusRewardRates() internal {
        bonusRewardRates[0] = 200;
        bonusRewardRates[1] = 500;
        bonusRewardRates[2] = 1000;
    }

    function _updateUserInfo() internal {
        uint pendingReward = _getPendingRewardAmount(msg.sender);
        if (pendingReward > 0) {
            IERC20Upgradeable(rewardERC20Token).transferFrom(address(this), msg.sender, pendingReward);
            userInfo[msg.sender].rewardEarned = userInfo[msg.sender].rewardEarned.add(pendingReward);
        }
        userInfo[msg.sender].lastRewardWithdrawl = block.timestamp;
    }

    function _getPendingRewardAmount(address _userAddress) internal view returns(uint) {
        if(!stakeHoldersList.contains(_userAddress)) {
            return 0;
        }

        if(userInfo[_userAddress].amountStaked == 0) {
            return 0;
        }

        uint stakedTimeDifference = block.timestamp.sub(userInfo[_userAddress].lastRewardWithdrawl);
        uint stakedAmountByUser = userInfo[_userAddress].amountStaked;
        uint stakedAmountInUSD = stakedAmountByUser.mul(uint256(_convertAmountToUSD())).div(1e8);

        uint _rewardRate;

        if(block.timestamp >= userInfo[_userAddress].depositDuration.add(30 days)) {
            _rewardRate = rewardRates[0];
        }
        else if(block.timestamp >= userInfo[_userAddress].depositDuration.add(180 days)) {
            _rewardRate = rewardRates[1];
        }
        else if(block.timestamp >= userInfo[_userAddress].depositDuration.add(365 days)) {
            _rewardRate = rewardRates[2];
        }
        else {
            _rewardRate = rewardRates[2];
        }

        if(stakedAmountInUSD >= 100) {
            _rewardRate = _rewardRate.add(bonusRewardRates[0]);
        }        
        else if(stakedAmountInUSD >= 500) {
            _rewardRate = _rewardRate.add(bonusRewardRates[1]);
        }
        else if(stakedAmountInUSD >= 1000) {
            _rewardRate = _rewardRate.add(bonusRewardRates[2]);
        }

        uint totalPendingReward = stakedAmountByUser.mul(_rewardRate).mul(stakedTimeDifference).div(stakingEndBlock).div(1e4);
        return totalPendingReward;
    }

    function _convertAmountToUSD() internal view returns(int) {
        (, int currentUSDPrice, , ,) = chainlinkAggregatorAddress.latestRoundData();
        return currentUSDPrice;
    }
}