// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error Error__NotEnoughOwners();
error Error__InvalidRequiredApprovals(uint256 minRequired, uint256 maxRequired);
error Error__OwnerNotUnique();
error Error__NotEnoughApprovals(uint256 minApprovals, uint256 actualApprovals);
error Error__TxAlreadyExists();
error Error__TxAlreadyApproved();
error Error__TxNotApproved();
error Error__TxAlreadyExecuted();
error Error__IsNotOwner();

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

    struct Approvals {
        uint256 ApprovalCount;
        mapping(address => bool) Owners;
        bool approved;
    }

    address[] public owners;
    mapping(address => bool) public isOwner;

    Transaction[] public transactions;
    uint256 public required; // number of approvals required
    mapping(uint256 => Approvals) public approvals;

    modifier onlyOwner() {
        if (!(isOwner[msg.sender])) {
            revert Error__IsNotOwner();
        }
        _;
    }

    modifier txExists(uint256 _txId) {
        if (_txId >= transactions.length) {
            revert Error__TxAlreadyExists();
        }
        _;
    }

    modifier notApproved(uint256 _txId) {
        if (approvals[_txId].approved) {
            revert Error__TxAlreadyApproved();
        }
        _;
    }

    modifier notExecuted(uint256 _txId) {
        if (transactions[_txId].executed) {
            revert Error__TxAlreadyExecuted();
        }
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
        approvals[_txId].ApprovalCount += 1;
        approvals[_txId].Owners[msg.sender] = true;

        emit Approve(msg.sender, _txId);
    }

    function _getApprovalCount(uint256 _txId)
        internal
        view
        returns (uint256 count)
    {
        count = approvals[_txId].ApprovalCount;
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
        if (!(approvals[_txId].Owners[msg.sender])) {
            revert Error__TxNotApproved();
        }

        approvals[_txId].Owners[msg.sender] = false;
        approvals[_txId].ApprovalCount -= 1;

        emit Revoke(msg.sender, _txId);
    }
}
