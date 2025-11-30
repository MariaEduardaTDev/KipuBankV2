// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Imports:
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title KipuBankV2 - Enhanced multi-asset vault with access control and oracle support
/// @author Maria Eduarda
/// @notice Multi-asset vault with ETH, ERC20, access-control, Chainlink price feed and USD-based deposit cap.
/// @dev This contract will evolve step-by-step throughout your project.

contract KipuBankV2 is AccessControl, ReentrancyGuard {
    // Roles:
    bytes32 public constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant CLIENT_ROLE  = keccak256("CLIENT_ROLE");

    // Oracle + Cap:
    /// @notice Chainlink price feed (ETH/USD)
    AggregatorV3Interface public priceFeed;

    /// @notice Maximum USD value allowed for total deposits (1e8 decimals)
    uint256 public bankCapUSD;

    /// @notice Total deposited value converted to USD (1e8 decimals)
    uint256 public totalDepositedUSD;
    bool public depositsPaused = false;

    // Events:
    event AccountCreated(address indexed user);
    event DepositMade(address indexed user, uint256 amount);
    event WithdrawalMade(address indexed user, uint256 amount);
    event TransferMade(address indexed from, address indexed to, uint256 amount);
    event TokenDeposit(address indexed user, address indexed token, uint256 amount);
    event TokenWithdrawal(address indexed user, address indexed token, uint256 amount);

    // Structs and Storage:
    struct Account {
        uint256 balance; // ETH balance in wei
        bool exists;
    }

    /// @notice ETH balances
    mapping(address => Account) private accounts;

    /// @notice ERC20 balances: user => token => amount
    mapping(address => mapping(address => uint256)) private tokenBalances;

    // Track allowed ERC20 tokens for deposits
    mapping(address => bool) public allowedTokens;

    // Constructor:
    constructor(address _priceFeed, uint256 _bankCapUSD) {
        require(_priceFeed != address(0), "Invalid price feed address");
        require(_bankCapUSD > 0, "Bank cap must be > 0");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        priceFeed = AggregatorV3Interface(_priceFeed);
        bankCapUSD = _bankCapUSD;
    }

    // Safety: reject direct plain transfers (force users to call deposit())
    receive() external payable {
        revert("Direct deposits disabled; use deposit()");
    }
    fallback() external payable {
        revert("Fallback: use deposit()");
    }

    // Modifiers:
    modifier respectsBankCap(uint256 usdValue) {
        require(totalDepositedUSD + usdValue <= bankCapUSD, "Bank cap exceeded");
        _;
    }

    // Chainlink Functions:
    /// @notice Returns latest ETH/USD price (8 decimals)
    function getLatestETHPrice() public view returns (int256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }

    /// @notice Converts wei → USD with 8 decimals
    function convertETHtoUSD(uint256 weiAmount) public view returns (uint256) {
        int256 price = getLatestETHPrice();
        require(price > 0, "Invalid price");
        // (wei * price) / 1e18
        return (weiAmount * uint256(price)) / 1e18;
    }

    // Account Management:
    function createAccount(address user) public onlyRole(ADMIN_ROLE) {
        require(user != address(0), "Invalid user address");
        require(!accounts[user].exists, "Account already exists");

        accounts[user] = Account({balance: 0, exists: true});
        _grantRole(CLIENT_ROLE, user);

        emit AccountCreated(user);
    }

    function getBalance() public view onlyRole(CLIENT_ROLE) returns (uint256) {
        return accounts[msg.sender].balance;
    }

    // ETH Deposit / Withdraw:
    function deposit() public payable onlyRole(CLIENT_ROLE) respectsBankCap(convertETHtoUSD(msg.value)) {
        require(accounts[msg.sender].exists, "Account does not exist");
        require(msg.value > 0, "Deposit must be > 0");

        require(!depositsPaused, "Deposits are paused");

        accounts[msg.sender].balance += msg.value;
        totalDepositedUSD += convertETHtoUSD(msg.value);

        emit DepositMade(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public nonReentrant onlyRole(CLIENT_ROLE) {
        require(accounts[msg.sender].exists, "Account does not exist");
        require(amount > 0, "Amount must be > 0");
        require(accounts[msg.sender].balance >= amount, "Insufficient funds");

        accounts[msg.sender].balance -= amount;
        totalDepositedUSD -= convertETHtoUSD(amount);

        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "ETH withdrawal failed");

        emit WithdrawalMade(msg.sender, amount);
    }

    // ERC20 Deposit / Withdraw:
    function depositERC20(address token, uint256 amount) public onlyRole(CLIENT_ROLE) {
        require(accounts[msg.sender].exists, "Account does not exist");
        require(!depositsPaused, "Deposits are paused");
        require(allowedTokens[token], "Token not allowed");
        require(amount > 0, "Amount must be > 0");

        bool ok = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(ok, "Token transfer failed");

        tokenBalances[msg.sender][token] += amount;

        emit TokenDeposit(msg.sender, token, amount);
    }

    function withdrawERC20(address token, uint256 amount) public nonReentrant onlyRole(CLIENT_ROLE) {
        require(accounts[msg.sender].exists, "Account does not exist");
        require(amount > 0, "Amount must be > 0");
        require(tokenBalances[msg.sender][token] >= amount, "Insufficient token balance");

        tokenBalances[msg.sender][token] -= amount;

        bool ok = IERC20(token).transfer(msg.sender, amount);
        require(ok, "Token withdraw failed");

        emit TokenWithdrawal(msg.sender, token, amount);
    }

    function getTokenBalance(address token) public view onlyRole(CLIENT_ROLE) returns (uint256) {
        return tokenBalances[msg.sender][token];
    }

    // Internal Transfers (ETH only):
    function transferTo(address to, uint256 amount) public nonReentrant onlyRole(CLIENT_ROLE) {
        require(to != address(0), "Invalid recipient");
        require(to != msg.sender, "Cannot transfer to yourself");
        require(accounts[msg.sender].exists, "Sender has no account");
        require(accounts[to].exists, "Recipient has no account");
        require(amount > 0, "Amount must be > 0");
        require(accounts[msg.sender].balance >= amount, "Insufficient funds");

        accounts[msg.sender].balance -= amount;
        accounts[to].balance += amount;

        emit TransferMade(msg.sender, to, amount);
    }

    /// @notice Manager can enable a token for deposits
    function allowToken(address token) public onlyRole(MANAGER_ROLE) {
        require(token != address(0), "Invalid token");
        allowedTokens[token] = true;
    }

    /// @notice Manager can disable a token (prevents new deposits; existing balances remain withdrawable)
    function disallowToken(address token) public onlyRole(MANAGER_ROLE) {
        require(allowedTokens[token], "Token not allowed");
        allowedTokens[token] = false;
    }

    /// @notice Manager can view ETH balance of any client
    function viewBalanceAsManager(address client) public view onlyRole(MANAGER_ROLE) returns (uint256) {
        require(accounts[client].exists, "Account not found");
        return accounts[client].balance;
    }

    /// @notice Manager can view ERC20 balance of any client
    function viewTokenBalanceAsManager(address client, address token) public view onlyRole(MANAGER_ROLE) returns (uint256) {
        require(accounts[client].exists, "Account not found");
        return tokenBalances[client][token];
    }

    /// @notice Manager can increase the USD cap (never decrease)
    function increaseBankCap(uint256 newCapUSD) public onlyRole(MANAGER_ROLE) {
        require(newCapUSD > bankCapUSD, "New cap must be higher");
        bankCapUSD = newCapUSD;
    }

    /// @notice Manager can pause all ETH and ERC20 deposits
    function pauseDeposits() public onlyRole(MANAGER_ROLE) {
        depositsPaused = true;
    }

    /// @notice Manager can unpause deposits
    function unpauseDeposits() public onlyRole(MANAGER_ROLE) {
        depositsPaused = false;
    }

    // Admin Role Controls:
    function grantManagerRole(address user) public onlyRole(ADMIN_ROLE) {
        _grantRole(MANAGER_ROLE, user);
    }

    function revokeManagerRole(address user) public onlyRole(ADMIN_ROLE) {
        _revokeRole(MANAGER_ROLE, user);
    }

    function revokeAnyRole(bytes32 role, address user) public onlyRole(ADMIN_ROLE) {
        _revokeRole(role, user);
    }
}
