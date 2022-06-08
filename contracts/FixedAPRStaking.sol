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

    uint public stakingEndTimestamp;

    uint public totalStakedInPool;

    EnumerableSet.AddressSet private stakeHoldersList;

    IERC20Upgradeable public rewardERC20Token;
    IERC20Upgradeable public stakedStableCoin;
    AggregatorV3Interface public chainlinkAggregatorAddress; // 0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF - rinkeby

    struct UserInfo {
        uint amountStaked;
        uint depositDuration;
        uint rewardEarned;
        uint lastRewardWithdrawl;
    }

    mapping(uint => uint) public rewardRates;
    mapping(uint => uint) public bonusRewardRates;
    mapping(address => UserInfo) public userInfo;

    function initialize (
        IERC20Upgradeable _rewardERC20Token,
        IERC20Upgradeable _stakedStableCoin,
        AggregatorV3Interface _chainlinkAggregatorAddress,
        uint _stakingEndTimestamp
    ) external initializer {
        rewardERC20Token = _rewardERC20Token;
        stakedStableCoin = _stakedStableCoin;
        chainlinkAggregatorAddress = _chainlinkAggregatorAddress;
        stakingEndTimestamp = _stakingEndTimestamp;
        _setRewardRates();
        _setBonusRewardRates();
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function depositInPool (uint _amount) external {
        UserInfo memory user = userInfo[msg.sender];
        require(_amount > 0, "depositStableCoin:: amount should be greater than zero");

        user.depositDuration = block.timestamp;

        IERC20Upgradeable(stakedStableCoin).transferFrom(msg.sender, address(this), _amount);

        _updateUserInfo();
        
        user.amountStaked = user.amountStaked.add(_amount);

        totalStakedInPool = totalStakedInPool.add(_amount);

        if(!stakeHoldersList.contains(msg.sender)) {
            stakeHoldersList.add(msg.sender);
        }
    }

    function withdrawFromPool(uint _amount) external {
        UserInfo memory user = userInfo[msg.sender];
        require(_amount <= userInfo[msg.sender].amountStaked, "withdrawFromPool:: can not withdraw more than your staked amount");

        _updateUserInfo();

        IERC20Upgradeable(stakedStableCoin).transfer(msg.sender, _amount);

        user.amountStaked = user.amountStaked.sub(_amount);

        totalStakedInPool = totalStakedInPool.sub(_amount);

        if(stakeHoldersList.contains(msg.sender)) {
            stakeHoldersList.remove(msg.sender);
        }
    }

    function claimERC20RewardTokens() external {
        _updateUserInfo();
    }

    function getPendingReward(address _userAddress) external view returns(uint) {
        uint pendingAmount = _getPendingRewardAmount(_userAddress);
        return pendingAmount; 
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
        UserInfo memory user = userInfo[msg.sender];
        uint pendingReward = _getPendingRewardAmount(msg.sender);
        if (pendingReward > 0) {
            IERC20Upgradeable(rewardERC20Token).transfer(msg.sender, pendingReward);
            user.rewardEarned = user.rewardEarned.add(pendingReward);
        }
        user.lastRewardWithdrawl = block.timestamp;
    }

    function _getPendingRewardAmount(address _userAddress) internal view returns(uint) {
        UserInfo memory user = userInfo[msg.sender];
        if(!stakeHoldersList.contains(_userAddress)) {
            return 0;
        }

        if(user.amountStaked == 0) {
            return 0;
        }

        uint stakedTimeDifference = block.timestamp.sub(user.lastRewardWithdrawl);
        uint stakedAmountByUser = user.amountStaked;
        uint stakedAmountInUSD = stakedAmountByUser.mul(uint256(_convertAmountToUSD())).div(1e8);

        uint _rewardRate;

        if(block.timestamp <= user.depositDuration.add(30 minutes)) {
            _rewardRate = rewardRates[0];
        }
        else if(block.timestamp > user.depositDuration.add(30 minutes) && block.timestamp <= user.depositDuration.add(180 minutes)) {
            _rewardRate = rewardRates[1];
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

        uint totalPendingReward = stakedAmountByUser.mul(_rewardRate).mul(stakedTimeDifference).div(stakingEndTimestamp).div(1e4);
        return totalPendingReward;
    }

    function _convertAmountToUSD() internal view returns(int) {
        (, int currentUSDPrice, , ,) = chainlinkAggregatorAddress.latestRoundData();
        return currentUSDPrice;
    }
}