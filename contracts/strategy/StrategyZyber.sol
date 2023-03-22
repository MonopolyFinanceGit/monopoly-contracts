// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {BaseStrategy} from "./BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StrategyStorage} from "./StrategyStorage.sol";
import {IZyberChef} from "../interfaces/IZyberChef.sol";
import {MonoMaster} from "../MonoMaster.sol";

contract StrategyZyber is BaseStrategy {
    using SafeERC20 for IERC20;
    IERC20 public constant rewardToken = IERC20(0x3B475F6f2f41853706afc9Fa6a6b8C5dF1a2724c);
    IZyberChef public immutable stakingContract;
    StrategyStorage public immutable strategyStorage;
    uint256 public immutable pid; // eth-usdc 3, 3pool 7
    uint256 public immutable pidMonopoly;
    uint256 public totalHarvested;
    mapping(address => uint256) public harvested;

    event Harvest(address indexed caller,address indexed to,uint256 harvestedAmount);
    constructor(MonoMaster _monoMaster,IERC20 _depositToken,uint256 _pid,uint256 _pidMonopoly,IZyberChef _stakingContract) BaseStrategy(_monoMaster, _depositToken) {
        pid = _pid;
        pidMonopoly = _pidMonopoly;
        stakingContract = _stakingContract;
        strategyStorage = new StrategyStorage();
        _depositToken.safeApprove(address(_stakingContract), MAX_UINT);
    }
    function checkReward() public view returns (uint256) {
        (, , , uint256[] memory amounts) = stakingContract.pendingTokens(pid,address(this));
        return amounts[0];
    }
    function pendingRewards(address user) public view returns (uint256) {
        uint256 userShares = monoMaster.userShares(pidMonopoly, user);
        uint256 unclaimedRewards = checkReward();
        uint256 rewardTokensPerShare = strategyStorage.rewardTokensPerShare();
        uint256 totalShares = monoMaster.totalShares(pidMonopoly);
        uint256 userRewardDebt = strategyStorage.rewardDebt(user);
        uint256 multiplier = rewardTokensPerShare;
        if (totalShares > 0) {
            multiplier = multiplier + ((unclaimedRewards * ACC_EARNING_PRECISION) / totalShares);
        }
        uint256 totalRewards = (userShares * multiplier) / ACC_EARNING_PRECISION;
        uint256 userPendingRewards = (totalRewards >= userRewardDebt) ? (totalRewards - userRewardDebt) : 0;
        return userPendingRewards;
    }

    function rewardTokens() external view virtual returns (address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(rewardToken);
        return (_rewardTokens);
    }

    function pendingTokens(uint256,address user,uint256) external view override returns (address[] memory, uint256[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(rewardToken);
        uint256[] memory _pendingAmounts = new uint256[](1);
        _pendingAmounts[0] = pendingRewards(user);
        return (_rewardTokens, _pendingAmounts);
    }
    function harvest() external {
        _claimRewards();
        _harvest(msg.sender, msg.sender);
    }
    function deposit(address caller,address to,uint256 tokenAmount,uint256 shareAmount) external override onlyOwner {
        _claimRewards();
        _harvest(caller, to);
        if (tokenAmount > 0) {
            stakingContract.deposit(pid, tokenAmount);
        }
        if (shareAmount > 0) {
            strategyStorage.increaseRewardDebt(to, shareAmount);
        }
    }

    function withdraw(address caller, address to, uint256 tokenAmount, uint256 shareAmount, uint256 withdrawalFeeBP) external override onlyOwner {
        _claimRewards();
        _harvest(caller, to);
        if (tokenAmount > 0) {
            stakingContract.withdraw(pid, tokenAmount);
            if (withdrawalFeeBP > 0) {
                uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) / 10000;
                depositToken.safeTransfer(monoMaster.performanceFeeAddress(), withdrawalFee);
                tokenAmount -= withdrawalFee;
            }
            depositToken.safeTransfer(to, tokenAmount);
        }
        if (shareAmount > 0) {
            strategyStorage.decreaseRewardDebt(to, shareAmount);
        }
    }
    function migrate(address newStrategy) external override onlyOwner {
        _claimRewards();
        (uint256 toWithdraw, , , ) = stakingContract.userInfo(pid,address(this));
        if (toWithdraw > 0) {
            stakingContract.withdraw(pid, toWithdraw);
            depositToken.safeTransfer(newStrategy, toWithdraw);
        }
        uint256 rewardsToTransfer = rewardToken.balanceOf(address(this));
        if (rewardsToTransfer > 0) {
            rewardToken.safeTransfer(newStrategy, rewardsToTransfer);
        }
        strategyStorage.transferOwnership(newStrategy);
    }
    function onMigration() external override onlyOwner {
        uint256 toStake = depositToken.balanceOf(address(this));
        stakingContract.deposit(pid, toStake);
    }
    function setAllowances() external override onlyOwner {
        depositToken.safeApprove(address(stakingContract), 0);
        depositToken.safeApprove(address(stakingContract), MAX_UINT);
    }
    function _claimRewards() internal {
        uint256 unclaimedRewards = checkReward();
        uint256 totalShares = monoMaster.totalShares(pidMonopoly);
        if (unclaimedRewards > 0 && totalShares > 0) {
            stakingContract.deposit(pid, 0);
            strategyStorage.increaseRewardTokensPerShare((unclaimedRewards * ACC_EARNING_PRECISION) / totalShares);
        }
    }
    function _harvest(address caller, address to) internal {
        uint256 userShares = monoMaster.userShares(pidMonopoly, caller);
        uint256 totalRewards = (userShares * strategyStorage.rewardTokensPerShare()) / ACC_EARNING_PRECISION;
        uint256 userRewardDebt = strategyStorage.rewardDebt(caller);
        uint256 userPendingRewards = (totalRewards >= userRewardDebt) ? (totalRewards - userRewardDebt) : 0;
        strategyStorage.setRewardDebt(caller, userShares);
        if (userPendingRewards > 0) {
            totalHarvested += userPendingRewards;
            if (performanceFeeBips > 0) {
                uint256 performanceFee = (userPendingRewards * performanceFeeBips) / MAX_BIPS;
                _safeRewardTokenTransfer(monoMaster.performanceFeeAddress(),performanceFee);
                userPendingRewards = userPendingRewards - performanceFee;
            }
            harvested[to] += userPendingRewards;
            emit Harvest(caller, to, userPendingRewards);
            _safeRewardTokenTransfer(to, userPendingRewards);
        }
    }
    function _safeRewardTokenTransfer(address user, uint256 amount) internal {
        uint256 rewardTokenBal = rewardToken.balanceOf(address(this));
        if (amount > rewardTokenBal) {
            rewardToken.safeTransfer(user, rewardTokenBal);
        } else {
            rewardToken.safeTransfer(user, amount);
        }
    }
}
