// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {MonopolyToken} from "./MonopolyToken.sol";
import {IEarningsReferral} from "./interfaces/IEarningsReferral.sol";

contract MonoMaster is Ownable {
    using SafeERC20 for IERC20;
    struct UserInfo {
        uint256 amount; // How many shares the user currently has
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lastDepositTimestamp; // Timestamp of the last deposit.
    }
    struct PoolInfo {
        IERC20 want; // Address of LP token contract.
        IStrategy strategy; // Address of strategy for pool
        uint256 allocPoint; // How many allocation points assigned to this pool. earnings to distribute per block.
        uint256 lastRewardTime; // Last block number that earnings distribution occurs.
        uint256 accEarningPerShare; // Accumulated earnings per share, times ACC_EARNING_PRECISION. See below.
        uint256 totalShares; //total number of shares in the pool
        uint256 lpPerShare; //number of LP tokens per share, times ACC_EARNING_PRECISION
        uint16 depositFeeBP; // Deposit fee in basis points
        uint16 withdrawFeeBP; // Withdraw fee in basis points
        bool isWithdrawFee; // if the pool has withdraw fee
    }
    MonopolyToken public immutable earningToken;    // The main reward token!
    uint256 public startTime;        // The block when mining starts.
    address public dev;     //development endowment
    address public performanceFeeAddress;     //performance fee address -- receives performance fees from strategies
    uint256 public earningsPerSecond;    // amount of reward emitted per second
    uint256 public totalAllocPoint = 0; // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public devMintBips = 1000;        //allocations to dev and nest addresses, expressed in BIPS
    bool public onlyApprovedContractOrEOAStatus;    //whether the onlyApprovedContractOrEOA is turned on or off
    uint256 internal constant ACC_EARNING_PRECISION = 1e18;
    uint256 internal constant MAX_BIPS = 10000;
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => bool) public approvedContracts;    //mappping for tracking contracts approved to build on top of this one
    mapping(uint256 => mapping(address => uint256)) public deposits;    //tracks historic deposits of each address. deposits[pid][user] is the total deposits for that user to that mono
    mapping(uint256 => mapping(address => uint256)) public withdrawals;        //tracks historic withdrawals of each address. withdrawals[pid][user] is the total withdrawals for that user from that mono
    uint16 public constant MAX_WITHDRAWAL_FEE_BP = 400;
    uint16 public MIN_WITHDRAWAL_FEE_BP = 100;
    uint16 public constant MAX_DEPOSIT_FEE_BP = 400;
    uint256 public MAX_LENEAR_DURATION = 28 days;
    IEarningsReferral public earningReferral;
    uint16 public referralCommissionRate = 300;
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 2000;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount,address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event DevSet(address indexed oldAddress, address indexed newAddress);
    event PerformanceFeeAddressSet(address indexed oldAddress, address indexed newAddress);
    event ReferralCommissionPaid(address indexed user,address indexed referrer,uint256 commissionAmount);
    modifier onlyApprovedContractOrEOA() {
        if (onlyApprovedContractOrEOAStatus) {
            require(tx.origin == msg.sender || approvedContracts[msg.sender],"MonoMaster::onlyApprovedContractOrEOA");
        }
        _;
    }
    constructor(MonopolyToken _earningToken, uint256 _startTime, address _dev, address _performanceFeeAddress, uint256 _earningsPerSecond) {
        require(_startTime > block.timestamp, "must start in future");
        earningToken = _earningToken;
        startTime = _startTime;
        dev = _dev;
        performanceFeeAddress = _performanceFeeAddress;
        earningsPerSecond = _earningsPerSecond;
        emit DevSet(address(0), _dev);
        emit PerformanceFeeAddressSet(address(0), _performanceFeeAddress);
    }
    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }
    function pendingEarnings(uint256 pid, address userAddr) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][userAddr];
        uint256 accEarningPerShare = pool.accEarningPerShare;
        uint256 poolShares = pool.totalShares;
        if (block.timestamp > pool.lastRewardTime && poolShares != 0) {
            uint256 earningsReward = (reward(pool.lastRewardTime, block.timestamp) * pool.allocPoint) / totalAllocPoint;
            accEarningPerShare = accEarningPerShare + ((earningsReward * ACC_EARNING_PRECISION) / poolShares);
        }
        return
            ((user.amount * accEarningPerShare) / ACC_EARNING_PRECISION) - user.rewardDebt;
    }
    function pendingTokens(uint256 pid, address user) external view returns (address[] memory, uint256[] memory) {
        uint256 earningAmount = pendingEarnings(pid, user);
        (address[] memory strategyTokens, uint256[] memory strategyRewards) = poolInfo[pid].strategy.pendingTokens(pid, user, earningAmount);
        uint256 rewardsLength = 1;
        for (uint256 j = 0; j < strategyTokens.length; j++) {
            if (strategyTokens[j] != address(0)) {
                rewardsLength += 1;
            }
        }
        address[] memory _rewardTokens = new address[](rewardsLength);
        uint256[] memory _pendingAmounts = new uint256[](rewardsLength);
        _rewardTokens[0] = address(earningToken);
        _pendingAmounts[0] = earningAmount;
        for (uint256 m = 0; m < strategyTokens.length; m++) {
            if (strategyTokens[m] != address(0)) {
                _rewardTokens[m + 1] = strategyTokens[m];
                _pendingAmounts[m + 1] = strategyRewards[m];
            }
        }
        return (_rewardTokens, _pendingAmounts);
    }
    function reward(uint256 _lastRewardTime, uint256 _currentTime) public view returns (uint256) {
        return ((_currentTime - _lastRewardTime) * earningsPerSecond);
    }
    function earningPerYear() public view returns (uint256) {
        return (earningsPerSecond * 31536000);
    }
    function earningPerYearToMonopoly(uint256 pid) public view returns (uint256) {
        return ((earningPerYear() * poolInfo[pid].allocPoint) / totalAllocPoint);
    }
    function totalShares(uint256 pid) public view returns (uint256) {
        return poolInfo[pid].totalShares;
    }
    function totalLP(uint256 pid) public view returns (uint256) {
        return ((poolInfo[pid].lpPerShare * totalShares(pid)) / ACC_EARNING_PRECISION);
    }
    function userShares(uint256 pid, address user) public view returns (uint256) {
        return userInfo[pid][user].amount;
    }
    function updatePool(uint256 pid) public {
        PoolInfo storage pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {
            uint256 poolShares = pool.totalShares;
            if (poolShares == 0 || pool.allocPoint == 0) {
                pool.lastRewardTime = block.timestamp;
                return;
            }
            uint256 earningReward = (reward(pool.lastRewardTime, block.timestamp) * pool.allocPoint) / totalAllocPoint;
            pool.lastRewardTime = block.timestamp;
            if (earningReward > 0) {
                uint256 toDev = (earningReward * devMintBips) / MAX_BIPS;
                pool.accEarningPerShare = pool.accEarningPerShare + ((earningReward * ACC_EARNING_PRECISION) / poolShares);
                earningToken.mint(dev, toDev);
                earningToken.mint(address(this), earningReward);
            }
        }
    }
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
    function deposit(uint256 pid, uint256 amount, address to, address _referrer) external onlyApprovedContractOrEOA {
        uint256 totalAmount = amount;
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        if (amount > 0) {
            UserInfo storage user = userInfo[pid][to];
            if (address(earningReferral) != address(0) && _referrer != address(0) && _referrer != msg.sender) {
                earningReferral.recordReferral(msg.sender, _referrer);
            }
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = (amount * pool.depositFeeBP) / 10000;
                pool.want.safeTransferFrom(address(msg.sender), performanceFeeAddress, depositFee);
                amount = amount - depositFee;
            }
            uint256 newShares = (amount * ACC_EARNING_PRECISION) / pool.lpPerShare;
            pool.want.safeTransferFrom(address(msg.sender), address(pool.strategy), amount);
            pool.strategy.deposit(msg.sender, to, amount, newShares);
            pool.totalShares = pool.totalShares + newShares;
            user.amount = user.amount + newShares;
            user.rewardDebt = user.rewardDebt + ((newShares * pool.accEarningPerShare) / ACC_EARNING_PRECISION);
            user.lastDepositTimestamp = block.timestamp;
            deposits[pid][to] += totalAmount;
            emit Deposit(msg.sender, pid, totalAmount, to);
        }
    }
    function withdraw(uint256 pid, uint256 amountShares, address to) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amountShares, "withdraw: not good");
        if (amountShares > 0) {
            uint256 lpFromShares = (amountShares * pool.lpPerShare) / ACC_EARNING_PRECISION;
            uint256 withdrawFeeBP;
            if (pool.isWithdrawFee) {
                withdrawFeeBP = getWithdrawFee(pid, msg.sender);
            }
            withdrawals[pid][to] += lpFromShares;
            pool.strategy.withdraw(msg.sender, to, lpFromShares, amountShares, withdrawFeeBP);
            user.amount = user.amount - amountShares;
            uint256 rewardDebtOfShares = ((amountShares * pool.accEarningPerShare) / ACC_EARNING_PRECISION);
            uint256 userRewardDebt = user.rewardDebt;
            user.rewardDebt = (userRewardDebt >= rewardDebtOfShares) ? (userRewardDebt - rewardDebtOfShares) : 0;
            pool.totalShares = pool.totalShares - amountShares;
            emit Withdraw(msg.sender, pid, amountShares, to);
        }
    }
    function harvest(uint256 pid, address to) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 accumulatedEarnings = (user.amount * pool.accEarningPerShare) / ACC_EARNING_PRECISION;
        uint256 pendings = accumulatedEarnings - user.rewardDebt;
        user.rewardDebt = accumulatedEarnings;
        if (pendings > 0) {
            safeEarningsTransfer(to, pendings);
            payReferralCommission(msg.sender, pendings);
        }
        pool.strategy.withdraw(msg.sender, to, 0, 0, 0);
        emit Harvest(msg.sender, pid, pendings);
    }
    function withdrawAndHarvest(uint256 pid, uint256 amountShares, address to) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amountShares, "withdraw: not good");
        uint256 accumulatedEarnings = (user.amount * pool.accEarningPerShare) / ACC_EARNING_PRECISION;
        uint256 pendings = accumulatedEarnings - user.rewardDebt;
        uint256 lpToSend = (amountShares * pool.lpPerShare) / ACC_EARNING_PRECISION;
        uint256 withdrawFeeBP;
        if (pool.isWithdrawFee) {
            withdrawFeeBP = getWithdrawFee(pid, msg.sender);
        }
        withdrawals[pid][to] += lpToSend;
        pool.strategy.withdraw(msg.sender, to, lpToSend, amountShares, withdrawFeeBP);
        user.amount = user.amount - amountShares;
        uint256 rewardDebtOfShares = ((amountShares * pool.accEarningPerShare) / ACC_EARNING_PRECISION);
        user.rewardDebt = accumulatedEarnings - rewardDebtOfShares;
        pool.totalShares = pool.totalShares - amountShares;
        if (pendings > 0) {
            safeEarningsTransfer(to, pendings);
            payReferralCommission(msg.sender, pendings);
        }
        emit Withdraw(msg.sender, pid, amountShares, to);
        emit Harvest(msg.sender, pid, pendings);
    }
    function emergencyWithdraw(uint256 pid, address to) external onlyApprovedContractOrEOA {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amountShares = user.amount;
        uint256 lpFromShares = (amountShares * pool.lpPerShare) / ACC_EARNING_PRECISION;
        uint256 withdrawFeeBP;
        if (pool.isWithdrawFee) {
            withdrawFeeBP = getWithdrawFee(pid, msg.sender);
        }
        withdrawals[pid][to] += lpFromShares;
        pool.strategy.withdraw(msg.sender, to, lpFromShares, amountShares, withdrawFeeBP);
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalShares = pool.totalShares - amountShares;
        emit EmergencyWithdraw(msg.sender, pid, amountShares, to);
    }
    function add(uint256 _allocPoint, uint16 _depositFeeBP, uint16 _withdrawFeeBP, IERC20 _want, bool _withUpdate, bool _isWithdrawFee, IStrategy _strategy) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(PoolInfo({want: _want,strategy: _strategy, allocPoint: _allocPoint, lastRewardTime: lastRewardTime, accEarningPerShare: 0, depositFeeBP: _depositFeeBP,withdrawFeeBP: _withdrawFeeBP, isWithdrawFee: _isWithdrawFee, totalShares: 0, lpPerShare: ACC_EARNING_PRECISION})
        );
    }
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate,bool _isWithdrawFee) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = (totalAllocPoint - poolInfo[_pid].allocPoint) + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].isWithdrawFee = _isWithdrawFee;
    }
    function migrateStrategy(uint256 pid, IStrategy newStrategy) external onlyOwner {
        PoolInfo storage pool = poolInfo[pid];
        pool.strategy.migrate(address(newStrategy));
        pool.strategy = newStrategy;
        newStrategy.onMigration();
    }
    function setStrategy(uint256 pid, IStrategy newStrategy, bool transferOwnership, address newOwner) external onlyOwner {
        PoolInfo storage pool = poolInfo[pid];
        if (transferOwnership) {
            pool.strategy.transferOwnership(newOwner);
        }
        pool.strategy = newStrategy;
    }
    function manualMint(address dest, uint256 amount) external onlyOwner {
        earningToken.mint(dest, amount);
    }
    function setDev(address _dev) external onlyOwner {
        require(_dev != address(0));
        emit DevSet(dev, _dev);
        dev = _dev;
    }
    function setPerfomanceFeeAddress(address _performanceFeeAddress) external onlyOwner {
        require(_performanceFeeAddress != address(0));
        emit PerformanceFeeAddressSet(
            performanceFeeAddress,
            _performanceFeeAddress
        );
        performanceFeeAddress = _performanceFeeAddress;
    }
    function setDevMintBips(uint256 _devMintBips) external onlyOwner {
        require(_devMintBips <= MAX_BIPS, "combined dev & nest splits too high");
        devMintBips = _devMintBips;
    }
    function setEarningsEmission(uint256 newEarningsPerSecond,bool withUpdate) external onlyOwner {
        if (withUpdate) {
            massUpdatePools();
        }
        earningsPerSecond = newEarningsPerSecond;
    }
    function modifyApprovedContracts(address[] calldata contracts, bool[] calldata statuses) external onlyOwner {
        require(contracts.length == statuses.length, "input length mismatch");
        for (uint256 i = 0; i < contracts.length; i++) {
            approvedContracts[contracts[i]] = statuses[i];
        }
    }
    function setOnlyApprovedContractOrEOAStatus(bool newStatus) external onlyOwner {
        onlyApprovedContractOrEOAStatus = newStatus;
    }
    function inCaseTokensGetStuck(uint256 pid,IERC20 token,address to,uint256 amount) external onlyOwner {
        IStrategy strat = poolInfo[pid].strategy;
        strat.inCaseTokensGetStuck(token, to, amount);
    }
    function setAllowances(uint256 pid) external onlyOwner {
        IStrategy strat = poolInfo[pid].strategy;
        strat.setAllowances();
    }
    function revokeAllowance(uint256 pid,address token,address spender) external onlyOwner {
        IStrategy strat = poolInfo[pid].strategy;
        strat.revokeAllowance(token, spender);
    }
    function setPerformanceFeeBips(uint256 pid,uint256 newPerformanceFeeBips) external onlyOwner {
        IStrategy strat = poolInfo[pid].strategy;
        strat.setPerformanceFeeBips(newPerformanceFeeBips);
    }
    function safeEarningsTransfer(address _to, uint256 _amount) internal {
        uint256 earningsBal = earningToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > earningsBal) {
            earningToken.mint(address(this), _amount - earningsBal);
        }
        transferSuccess = earningToken.transfer(_to, _amount);
        require(transferSuccess, "safeEarningsTransfer: transfer failed");
    }
    function getWithdrawFee(uint256 _pid,address _user) public view returns (uint16) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        if (!pool.isWithdrawFee) return 0;
        uint256 elapsed = block.timestamp - user.lastDepositTimestamp;
        uint16 DEDUCTABLE_FEE_BP = MAX_WITHDRAWAL_FEE_BP - MIN_WITHDRAWAL_FEE_BP;
        uint16 deductionFee = uint16(((elapsed * 1e18) * DEDUCTABLE_FEE_BP) / MAX_LENEAR_DURATION / 1e18);
        if (deductionFee > DEDUCTABLE_FEE_BP) return MIN_WITHDRAWAL_FEE_BP; // MAX - DEDUCTABLE
        return MAX_WITHDRAWAL_FEE_BP - deductionFee;
    }
    function setWithdrawFee(uint256 _maxLenearDuration) public onlyOwner {
        MAX_LENEAR_DURATION = _maxLenearDuration;
    }
    function setEarningsReferral(
        IEarningsReferral _earningReferral
    ) public onlyOwner {
        earningReferral = _earningReferral;
    }
    function setReferralCommissionRate(uint16 _referralCommissionRate) public onlyOwner {
    require(_referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE,"setReferralCommissionRate: invalid referral commission rate basis points");
        referralCommissionRate = _referralCommissionRate;
    }
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (
            address(earningReferral) != address(0) && referralCommissionRate > 0
        ) {
            address referrer = earningReferral.getReferrer(_user);
            uint256 commissionAmount = (_pending * referralCommissionRate) / 10000;
            if (referrer != address(0) && commissionAmount > 0) {
                earningToken.mint(referrer, commissionAmount);
                earningReferral.recordReferralCommission(referrer,commissionAmount);
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }
}
