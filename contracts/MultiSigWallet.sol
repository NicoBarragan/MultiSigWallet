// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error Error__NotEnoughOwners();
error Error__InvalidRequiredApprovals(uint256 minRequired, uint256 maxRequired);
error Error__OwnerNotUnique();
error Error__NotEnoughApprovals(uint256 minApprovals, uint256 actualApprovals);

contract MultiSigWallet is ReentrancyGuard {
    event Deposit(address indexed sender, uint256 amount);
    event Submit(uint256 indexed txId);
    event Approve(address indexed owner, uint256 indexed txId);
    event Revoke(address indexed owner, uint256 indexed txId);
    event Execute(uint256 indexed txId);

    struct Transaction {
        address sender;
        uint256 value;
        bytes data;
        bool executed;
    }

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public required; // number of approvals required

    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public approved;
    // mapping(txIdx => mapping(sender => isOnwer))

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Only owner can call this function");
        _;
    }

    modifier txExists(uint256 _txId) {
        require(_txId < transactions.length, "Transaction does not exist");
        _;
    }

    modifier notApproved(uint256 _txId) {
        require(!approved[_txId][msg.sender], "Transaction already approved");
        _;
    }

    modifier notExecuted(uint256 _txId) {
        require(!transactions[_txId].executed, "Transaction already executed");
        _;
    }

    constructor(address[] memory _owners, uint256 _required) {
        if (_owners.length <= 0) {
            revert Error__NotEnoughOwners();
        }

        if (_required == 0 || _required > _owners.length) {
            revert Error__InvalidRequiredApprovals(1, _owners.length);
        }

        for (uint256 i = 0; i < owners.length; i++) {
            require(
                _owners[i] != address(0),
                "Owner cannot be the zero address"
            );
            address owner = _owners[i];

            if (isOwner[_owners[i]]) {
                revert Error__OwnerNotUnique();
            }
            isOwner[owner] = true;
            owners.push(owner);
        }

        required = _required;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    function submit(
        address _sender,
        uint256 _value,
        bytes calldata _data // calldata because is external and is cheaper in gas
    ) external onlyOwner {
        transactions.push(
            Transaction({
                sender: _sender,
                value: _value,
                data: _data,
                executed: false
            })
        );
        emit Submit(transactions.length - 1);
    }

    function approve(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notApproved(_txId)
        notExecuted(_txId)
    {
        approved[_txId][msg.sender] = true;
        emit Approve(msg.sender, _txId);
    }

    function _getApprovalCount(uint256 _txId)
        private
        view
        returns (uint256 count)
    {
        for (uint256 i = 0; i < owners.length; i++) {
            if (approved[_txId][owners[i]]) {
                count += 1;
            }
        }
    }

    function execute(uint256 _txId)
        external
        nonReentrant
        txExists(_txId)
        notExecuted(_txId)
    {
        uint256 approvalCount = _getApprovalCount(_txId);
        if (approvalCount < required) {
            revert Error__NotEnoughApprovals(required, approvalCount);
        }
        transactions[_txId].executed = true;

        (bool success, ) = transactions[_txId].sender.call{
            value: transactions[_txId].value
        }(transactions[_txId].data);
        require(success, "Transaction failed");

        emit Execute(_txId);
    }

    function revoke(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
    {
        require(approved[_txId][msg.sender], "Transaction not approved");
        approved[_txId][msg.sender] = false;

        emit Revoke(msg.sender, _txId);
    }
}
