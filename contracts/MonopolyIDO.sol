// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
contract MonopolyIDO is ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        bool claimed; // default false
    }
    address public adminAddress;
    IERC20 public lpToken;
    IERC20 public offeringToken;
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public raisingAmount;
    uint256 public offeringAmount;
    uint256 public totalAmount;
    mapping(address => UserInfo) public userInfo;
    address[] public addressList;
    event Deposit(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 offeringAmount, uint256 excessAmount);

    constructor(IERC20 _lpToken, IERC20 _offeringToken, uint256 _startBlock, uint256 _endBlock, uint256 _offeringAmount, uint256 _raisingAmount, address _adminAddress) {
        lpToken = _lpToken;
        offeringToken = _offeringToken;
        startBlock = _startBlock;
        endBlock = _endBlock;
        offeringAmount = _offeringAmount;
        raisingAmount = _raisingAmount;
        totalAmount = 0;
        adminAddress = _adminAddress;
    }
    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }
    function setOfferingAmount(uint256 _offerAmount) public onlyAdmin {
        require(block.number < startBlock, "no");
        offeringAmount = _offerAmount;
    }
    function setRaisingAmount(uint256 _raisingAmount) public onlyAdmin {
        require(block.number < startBlock, "no");
        raisingAmount = _raisingAmount;
    }
    function deposit(uint256 _amount) public {
        require(block.number > startBlock && block.number < endBlock, "not ifo time");
        require(_amount > 0, "need _amount > 0");
        lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        if (userInfo[msg.sender].amount == 0) {
            addressList.push(address(msg.sender));
        }
        userInfo[msg.sender].amount = userInfo[msg.sender].amount + _amount;
        totalAmount = totalAmount + _amount;
        emit Deposit(msg.sender, _amount);
    }
    function harvest() public nonReentrant {
        require(block.number > endBlock, "not harvest time");
        require(userInfo[msg.sender].amount > 0, "have you participated?");
        require(!userInfo[msg.sender].claimed, "nothing to harvest");
        uint256 offeringTokenAmount = getOfferingAmount(msg.sender);
        uint256 refundingTokenAmount = getRefundingAmount(msg.sender);
        offeringToken.safeTransfer(address(msg.sender), offeringTokenAmount);
        if (refundingTokenAmount > 0) {
            lpToken.safeTransfer(address(msg.sender), refundingTokenAmount);
        }
        userInfo[msg.sender].claimed = true;
        emit Harvest(msg.sender, offeringTokenAmount, refundingTokenAmount);
    }
    function hasHarvest(address _user) external view returns (bool) {
        return userInfo[_user].claimed;
    }
    function getUserAllocation(address _user) public view returns (uint256) {
        return (userInfo[_user].amount * 1e12) / totalAmount / 1e6;
    }
    function getOfferingAmount(address _user) public view returns (uint256) {
        if (totalAmount > raisingAmount) {
            uint256 allocation = getUserAllocation(_user);
            return (offeringAmount * allocation) / 1e6;
        } else {
            return (userInfo[_user].amount * offeringAmount) / raisingAmount;
        }
    }
    function getRefundingAmount(address _user) public view returns (uint256) {
        if (totalAmount <= raisingAmount) {
            return 0;
        }
        uint256 allocation = getUserAllocation(_user);
        uint256 payAmount = (raisingAmount * allocation) / 1e6;
        return userInfo[_user].amount - payAmount;
    }
    function getAddressListLength() external view returns (uint256) {
        return addressList.length;
    }
    function finalWithdraw(uint256 _lpAmount,uint256 _offerAmount) public onlyAdmin {
        require(_lpAmount < lpToken.balanceOf(address(this)), "not enough token 0");
        require(_offerAmount < offeringToken.balanceOf(address(this)),"not enough token 1");
        lpToken.safeTransfer(address(msg.sender), _lpAmount);
        offeringToken.safeTransfer(address(msg.sender), _offerAmount);
    }
}
