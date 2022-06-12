//SPDX-License-Identifier: Undefined

pragma solidity ^0.8.0;

/// @title Fixed APR Staking Smartcontract

/// @notice imports
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract StableCoinStaking is Initializable, OwnableUpgradeable, UUPSUpgradeable {

    /// @dev Using oz SafeMath library for uint256
    using SafeMath for uint256;

    /// @dev Using oz Enumberset for AddressSet
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Staking end-time in unix timestamp
    uint public stakingEndTimestamp;

    /// @dev Total amount staked in stkaing contract
    uint public totalStakedInPool;

    /// @dev Creating stake holders list(array) using EnumberableSet.AddressSet
    EnumerableSet.AddressSet private stakeHoldersList;

    /// @dev Initializing reward token's contract instance
    IERC20Upgradeable public rewardERC20Token;

    /// @dev Initializing Stable coin's contract instance
    IERC20Upgradeable public stakedStableCoin;

    /// @dev Initializing Chainlink's Aggregator contract instance
    AggregatorV3Interface public chainlinkAggregatorAddress; // 0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF - rinkeby

    /**
        @notice Struct Storing user's information
        @dev amountStaked: total amount staked by user
        @dev depositDuration: earliest unix timestamp of user's stake
        @dev rewardEarned: total reward token's earned by user 
        @dev lastRewardWithdrawl: earliest unix timestamp of user's reward withdrawl
    */
    struct UserInfo {
        uint amountStaked;
        uint depositDuration;
        uint rewardEarned;
        uint lastRewardWithdrawl;
    }

    /// @dev storage of reward rates
    mapping(uint => uint) public rewardRates;

    /// @dev storage of bonus reward rates
    mapping(uint => uint) public bonusRewardRates;

    /// @dev storage of user information struct
    mapping(address => UserInfo) public userInfo;

    /**
        @notice initializing staking contract
        @dev UUPS ugradeable smartcontract
        @dev utilizes hardhat-upgrade plugins
        @param _rewardERC20Token: reward token smartcontract address
        @param _stakedStableCoin: stable coin smartcontract address
        @param _chainlinkAggregatorAddress: chainlink's aggregator address
        @param _stakingEndTimestamp: unix timestamp of staking duration
    */
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

    /// @notice UUPS upgrade mandatory function: To authorize the owner to upgrade the contract 
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
        @notice deposit stable coin in staking contract
        @dev user must approve staking contract for using there stable coins
        @param _amount: amount to stake in wei
    */
    function depositInPool (uint _amount) external {
        UserInfo storage user = userInfo[msg.sender];
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

    /**
        @notice withdraw stable coin from staking contract along with reward tokens(msg.sender)
        @param _amount: amount to withdraw in wei
    */
    function withdrawFromPool(uint _amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(_amount <= user.amountStaked, "withdrawFromPool:: can not withdraw more than your staked amount");

        _updateUserInfo();

        IERC20Upgradeable(stakedStableCoin).transfer(msg.sender, _amount);

        user.amountStaked = user.amountStaked.sub(_amount);

        totalStakedInPool = totalStakedInPool.sub(_amount);

        if(stakeHoldersList.contains(msg.sender)) {
            stakeHoldersList.remove(msg.sender);
        }
    }

    /**
        @notice withdraw reward tokens earned(msg.sender)
    */
    function claimERC20RewardTokens() external {
        _updateUserInfo();
    }

    /**
        @notice fetch total rewards earned by user
        @param _userAddress: user's address of whom you want to check rewards for
        @return uint: pending rewards for @param
    */
    function getPendingReward(address _userAddress) external view returns(uint) {
        uint pendingAmount = _getPendingRewardAmount(_userAddress);
        return pendingAmount; 
    }

    /**
        @notice set reward rates based on staked duration
        @dev internal function
        @dev to be called in initialize function
    */
    function _setRewardRates() internal {
        rewardRates[0] = 500;
        rewardRates[1] = 1000;
        rewardRates[2] = 1500;
    }

    /**
        @notice set bonus reward rates based on staked amount
        @dev internal function
        @dev to be called in initialize function
    */
    function _setBonusRewardRates() internal {
        bonusRewardRates[0] = 200;
        bonusRewardRates[1] = 500;
        bonusRewardRates[2] = 1000;
    }

    /**
        @notice update user information and transfer pending reward tokens (msg.sender)
        @dev internal function
        @dev smartcontract must have enough reward token balance
    */
    function _updateUserInfo() internal {
        UserInfo storage user = userInfo[msg.sender];
        uint pendingReward = _getPendingRewardAmount(msg.sender);
        if (pendingReward > 0) {
            IERC20Upgradeable(rewardERC20Token).transfer(msg.sender, pendingReward);
            user.rewardEarned = user.rewardEarned.add(pendingReward);
        }
        user.lastRewardWithdrawl = block.timestamp;
    }

    /**
        @notice get pending rewards generated by user(msg.sender)
        @dev internal function
        @param _userAddress: user's address of whom you want to check rewards for
        @return uint: pending rewards generated by users
    */
    function _getPendingRewardAmount(address _userAddress) internal view returns(uint) {
        UserInfo storage user = userInfo[msg.sender];
        if(!stakeHoldersList.contains(_userAddress)) {
            return 0;
        }

        if(user.amountStaked == 0) {
            return 0;
        }

        uint stakedTimeDifference = block.timestamp.sub(userInfo[msg.sender].lastRewardWithdrawl);
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

    /**
        @notice fetch current price of stable-coin/USD
        @dev internal function
        @return uint: current USD equivalent price of stable coin
    */
    function _convertAmountToUSD() internal view returns(int) {
        (, int currentUSDPrice, , ,) = chainlinkAggregatorAddress.latestRoundData();
        return currentUSDPrice;
    }
}