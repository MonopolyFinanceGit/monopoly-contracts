// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {MonoMaster} from "../MonoMaster.sol";

contract BaseStrategy is IStrategy, Ownable {
    using SafeERC20 for IERC20;
    MonoMaster public immutable monoMaster;
    IERC20 public immutable depositToken;
    uint256 public performanceFeeBips;
    uint256 internal constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 internal constant ACC_EARNING_PRECISION = 1e18;
    uint256 internal constant MAX_BIPS = 10000;
    constructor(MonoMaster _monoMaster, IERC20 _depositToken) {
        monoMaster = _monoMaster;
        depositToken = _depositToken;
        transferOwnership(address(_monoMaster));
    }
    function pendingTokens(uint256,address,uint256) external view virtual override returns (address[] memory, uint256[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(0);
        uint256[] memory _pendingAmounts = new uint256[](1);
        _pendingAmounts[0] = 0;
        return (_rewardTokens, _pendingAmounts);
    } 
    function deposit(address,address,uint256,uint256) external virtual override onlyOwner {}
    function withdraw(address,address to,uint256 tokenAmount,uint256,uint256 withdrawalFeeBP) external virtual override onlyOwner {
        if (tokenAmount > 0) {
            if (withdrawalFeeBP > 0) {
                uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) / 10000;
                depositToken.safeTransfer(monoMaster.performanceFeeAddress(),withdrawalFee);
                tokenAmount -= withdrawalFee;
            }
            depositToken.safeTransfer(to, tokenAmount);
        }
    }

    function inCaseTokensGetStuck(IERC20 token,address to,uint256 amount) external virtual override onlyOwner {
        require(amount > 0, "cannot recover 0 tokens");
        require(address(token) != address(depositToken),"cannot recover deposit token");
        token.safeTransfer(to, amount);
    }
    function setAllowances() external virtual override onlyOwner {}
    function revokeAllowance(address token,address spender) external virtual override onlyOwner {
        IERC20(token).safeApprove(spender, 0);
    }
    function migrate(address newStrategy) external virtual override onlyOwner {
        uint256 toTransfer = depositToken.balanceOf(address(this));
        depositToken.safeTransfer(newStrategy, toTransfer);
    }
    function onMigration() external virtual override onlyOwner {}
    function emergencyWithdraw(address,address to,uint256 tokenAmount,uint256,uint256) external virtual override onlyOwner {}
    function transferOwnership(address newOwner) public virtual override(Ownable, IStrategy) onlyOwner {
        Ownable.transferOwnership(newOwner);
    }
    function setPerformanceFeeBips(uint256 newPerformanceFeeBips) external virtual override onlyOwner {
        require(newPerformanceFeeBips <= MAX_BIPS, "input too high");
        performanceFeeBips = newPerformanceFeeBips;
    }
}
