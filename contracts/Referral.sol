// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEarningsReferral} from "./interfaces/IEarningsReferral.sol";

contract Referral is IEarningsReferral, Ownable {
    using SafeERC20 for IERC20;
    mapping(address => bool) public operators;
    mapping(address => address) public referrers; // user address => referrer address
    mapping(address => uint256) public referralsCount; // referrer address => referrals count
    mapping(address => uint256) public totalReferralCommissions; // referrer address => total referral commissions
    event ReferralRecorded(address indexed user, address indexed referrer);
    event ReferralCommissionRecorded(
        address indexed referrer,
        uint256 commission
    );
    event OperatorUpdated(address indexed operator, bool indexed status);
    modifier onlyOperator() {
        require(operators[msg.sender], "Operator: caller is not the operator");
        _;
    }
    function recordReferral(address _user, address _referrer) public override onlyOperator {
        if (_user != address(0) &&_referrer != address(0) && _user != _referrer && referrers[_user] == address(0)) {
            referrers[_user] = _referrer;
            referralsCount[_referrer] += 1;
            emit ReferralRecorded(_user, _referrer);
        }
    }
    function recordReferralCommission(address _referrer, uint256 _commission) public override onlyOperator {
        if (_referrer != address(0) && _commission > 0) {
            totalReferralCommissions[_referrer] += _commission;
            emit ReferralCommissionRecorded(_referrer, _commission);
        }
    }
    function getReferrer(address _user) public view override returns (address) {
        return referrers[_user];
    }
    function updateOperator(address _operator, bool _status) external onlyOwner {
        operators[_operator] = _status;
        emit OperatorUpdated(_operator, _status);
    }
    function recoverERC20Token(IERC20 _token, uint256 _amount, address _to) external onlyOwner {
        _token.safeTransfer(_to, _amount);
    }
}
