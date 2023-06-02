// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPolyMaster {
    function MAXIMUM_REFERRAL_COMMISSION_RATE() external view returns (uint16);

    function MAX_DEPOSIT_FEE_BP() external view returns (uint16);

    function MAX_LINEAR_DURATION() external view returns (uint256);

    function MAX_WITHDRAW_FEE_BP() external view returns (uint16);

    function actionFeeAddress() external view returns (address);

    function add(
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        uint16 _withdrawFeeBP,
        address _want,
        bool _withUpdate,
        bool _isWithdrawFee,
        address _strategy
    ) external;

    function approvedContracts(address) external view returns (bool);

    function deposit(
        uint256 pid,
        uint256 amount,
        address to,
        address _referrer
    ) external;

    function dev() external view returns (address);

    function devMintBips() external view returns (uint256);

    function earningPerYear() external view returns (uint256);

    function earningPerYearToMonopoly(
        uint256 pid
    ) external view returns (uint256);

    function earningReferral() external view returns (address);

    function earningToken() external view returns (address);

    function earningsPerSecond() external view returns (uint256);

    function emergencyWithdraw(uint256 pid, address to) external;

    function endTime() external view returns (uint256);

    function getWithdrawFee(
        uint256 _pid,
        address _user
    ) external view returns (uint16);

    function harvest(uint256 pid, address to) external;

    function inCaseTokenGetStuck(address token, uint256 amount) external;

    function inCaseTokensGetStuck(
        uint256 pid,
        address token,
        address to,
        uint256 amount
    ) external;

    function initialize(
        address _earningToken,
        uint256 _startTime,
        uint256 _endTime,
        address _dev,
        address _performanceFeeAddress,
        address _actionFeeAddress,
        uint256 _earningsPerSecond,
        address _sPolyToken
    ) external;

    function isInitialized() external view returns (bool);

    function massUpdatePools() external;

    function onlyApprovedContractOrEOAStatus() external view returns (bool);

    function owner() external view returns (address);

    function pendingEarnings(
        uint256 pid,
        address userAddr
    ) external view returns (uint256);

    function performanceFeeAddress() external view returns (address);

    function poolInfo(
        uint256
    )
        external
        view
        returns (
            address want,
            address strategy,
            uint256 allocPoint,
            uint256 lastRewardTime,
            uint256 accEarningPerShare,
            uint256 totalShares,
            uint256 lpPerShare,
            uint16 depositFeeBP,
            uint16 withdrawFeeBP,
            bool isWithdrawFee
        );

    function poolLength() external view returns (uint256);

    function referralCommissionRate() external view returns (uint16);

    function renounceOwnership() external;

    function revokeAllowance(
        uint256 pid,
        address token,
        address spender
    ) external;

    function reward(
        uint256 _lastRewardTime,
        uint256 _currentTime
    ) external view returns (uint256);

    function sPolyToken() external view returns (address);

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        uint16 _withdrawFeeBP,
        bool _withUpdate,
        bool _isWithdrawFee
    ) external;

    function setActionFeeAddress(address _actionFeeAddress) external;

    function setAllowances(uint256 pid) external;

    function setDev(address _dev) external;

    function setDevMintBips(uint256 _devMintBips) external;

    function setEarningsEmission(
        uint256 newEarningsPerSecond,
        bool withUpdate
    ) external;

    function setEarningsReferral(address _earningReferral) external;

    function setOnlyApprovedContractOrEOAStatus(bool newStatus) external;

    function setPerfomanceFeeAddress(address _performanceFeeAddress) external;

    function setPerformanceFeeBips(
        uint256 pid,
        uint256 newPerformanceFeeBips
    ) external;

    function setReferralCommissionRate(uint16 _referralCommissionRate) external;

    function setSPoly(address _sPolyToken) external;

    function setStakedRewardRatio(uint256 _stakedRewardRatio) external;

    function setWithdrawalDuration(uint256 _maxLenearDuration) external;

    function stakedRewardRatio() external view returns (uint256);

    function startTime() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function totalLP(uint256 pid) external view returns (uint256);

    function totalShares(uint256 pid) external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function updatePool(uint256 pid) external;

    function userInfo(
        uint256,
        address
    )
        external
        view
        returns (
            uint256 amount,
            uint256 rewardDebt,
            uint256 lastDepositTimestamp
        );

    function userShares(
        uint256 pid,
        address user
    ) external view returns (uint256);

    function withdraw(uint256 pid, uint256 amountShares, address to) external;

    function withdrawAndHarvest(
        uint256 pid,
        uint256 amountShares,
        address to
    ) external;
}
