// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract TokenLock {
    address public admin;
    IERC20 public token;

    struct Lock {
        uint256 amount;
        uint256 entry;
        uint256 period;
    }

    mapping(uint256 => Lock) public lockInfo;
    mapping(address => mapping(uint256 => Lock)) public locks;

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    function updateAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid address");
        admin = newAdmin;
    }

    function setToken(address _tokenAddress) external onlyAdmin {
        token = IERC20(_tokenAddress);
    }

    function setLockDetails(uint256 projectId, uint256 _amount, uint256 _period) external onlyAdmin {
        Lock memory lock;
        lock = Lock(_amount, block.timestamp, _period);
        lockInfo[projectId] = lock;
    }

    function lockTokens(uint256 projectId) external {
        require(locks[msg.sender][projectId].amount == 0, "Tokens already locked");
        require(token.transferFrom(msg.sender, address(this), lockInfo[projectId].amount), "Transfer failed");

        locks[msg.sender][projectId].amount = lockInfo[projectId].amount;
        locks[msg.sender][projectId].entry = lockInfo[projectId].entry;
        locks[msg.sender][projectId].period = lockInfo[projectId].period;
    }

    function unlockTokens(uint256 projectId) external {
        require(locks[msg.sender][projectId].amount > 0, "No tokens to unlock");
        require(block.timestamp - locks[msg.sender][projectId].entry > locks[msg.sender][projectId].period, "Lock period has not ended");

        require(token.transfer(msg.sender, locks[msg.sender][projectId].amount), "Transfer failed");
        delete locks[msg.sender][projectId];
    }
}