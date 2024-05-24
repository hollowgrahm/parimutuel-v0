// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Parimutuel {
    address private admin;
    AggregatorV3Interface private priceOracle;
    IERC20 private settlementToken;

    uint256 public shortTokens;
    uint256 public longTokens;
    uint256 public shortProfits;
    uint256 public longProfits;
    uint256 public shortShares;
    uint256 public longShares;

    mapping(address => uint256) public balance;
    mapping(address => Position) public shorts;
    mapping(address => Position) public longs;

    uint256 public constant FUNDING_INTERVAL = 21600;
    uint256 public constant FUNDING_PERIODS = 1460;
    uint256 public constant MIN_LEVERAGE = 1;
    uint256 public constant MAX_LEVERAGE = 100;
    uint256 public constant PRECISION = 10 ** 18;
    uint256 public constant MIN_MARGIN = PRECISION;

    struct Position {
        bool active;
        uint256 margin;
        uint256 leverage;
        uint256 tokens;
        uint256 entry;
        uint256 liquidation;
        uint256 profit;
        uint256 shares;
        uint256 funding;
    }

    error AmountMustBeGreaterThanZero();
    error TransferFailed();
    error InsufficientBalance();
    error InsufficientMargin();
    error InvalidLeverage();

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event OpenShortPosition(
        address indexed user,
        uint256 margin,
        uint256 leverage,
        uint256 entryPrice
    );

    constructor(address _priceOracle, address _settlementToken) {
        priceOracle = AggregatorV3Interface(_priceOracle);
        settlementToken = IERC20(_settlementToken);
        admin = msg.sender;
    }

    modifier hasSufficientBalance(uint256 amount) {
        if (balance[msg.sender] < amount) {
            revert InsufficientBalance();
        }
        _;
    }

    function currentPrice() public view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(priceOracle)
            .latestRoundData();
        if (price < 0) price = 0;
        return uint256(price);
    }

    function deposit(uint256 amount) public {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        bool success = settlementToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert TransferFailed();
        }

        balance[msg.sender] += amount;
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) public hasSufficientBalance(amount) {
        if (amount == 0) {
            revert AmountMustBeGreaterThanZero();
        }

        balance[msg.sender] -= amount;

        bool success = settlementToken.transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed();
        }

        emit Withdraw(msg.sender, amount);
    }

    function openShortPosition(
        uint256 margin,
        uint256 leverage
    ) public hasSufficientBalance(margin) {
        if (margin < MIN_MARGIN) {
            revert InsufficientMargin();
        }
        if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE) {
            revert InvalidLeverage();
        }

        uint256 tokens = margin * leverage;
        uint256 entryPrice = currentPrice();

        balance[msg.sender] -= margin;

        uint256 liquidationPrice = (entryPrice * (100 + leverage)) / 100;
        uint256 profitPrice = (entryPrice * (100 - leverage)) / 100;
        uint256 shares = sqrt(shortTokens + tokens) - shortShares;

        uint256 totalTokens = shortTokens + tokens;
        uint256 dilution = (tokens * PRECISION) / totalTokens;
        uint256 fee = (dilution * margin) / PRECISION;

        margin -= fee;
        balance[admin] += fee;

        shorts[msg.sender] = Position({
            active: true,
            margin: margin,
            leverage: leverage,
            tokens: tokens,
            entry: entryPrice,
            liquidation: liquidationPrice,
            profit: profitPrice,
            shares: shares,
            funding: block.timestamp + FUNDING_INTERVAL
        });

        shortTokens += tokens;
        shortShares += shares;

        emit OpenShortPosition(msg.sender, margin, leverage, entryPrice);
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return z;
    }
}
