// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Math} from "./libraries/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

contract Parimutuel is Math {
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
    error NoActiveShort();
    error NoActiveLong();
    error NotLiquidatable();
    error NotCloseableAtLoss();
    error NotCloseableAtProfit();
    error FundingRateNotDue();

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event OpenShort(Position indexed short);
    event ShortLiquidated(Position indexed short);
    event ShortClosedAtLoss(Position indexed short);
    event ShortClosedAtProfit(Position indexed short);
    event OpenLong(Position indexed short);
    event LongLiquidated(Position indexed short);
    event LongClosedAtLoss(Position indexed short);
    event LongClosedAtProfit(Position indexed short);
    event ShortFundingPaid(Position indexed short);
    event LongFundingPaid(Position indexed long);
    event MarginAddedShort(Position indexed short);
    event MarginAddedLong(Position indexed short);

    constructor(address _priceOracle, address _settlementToken) {
        priceOracle = AggregatorV3Interface(_priceOracle);
        settlementToken = IERC20(_settlementToken);
        admin = msg.sender;
    }

    modifier sufficientBalance(uint256 amount) {
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
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        bool success = settlementToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) revert TransferFailed();

        balance[msg.sender] += amount;
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) public sufficientBalance(amount) {
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        balance[msg.sender] -= amount;

        bool success = settlementToken.transfer(msg.sender, amount);
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, amount);
    }

    function openShort(
        uint256 margin,
        uint256 leverage
    ) public sufficientBalance(margin) {
        if (margin < MIN_MARGIN) revert InsufficientMargin();
        if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE) {
            revert InvalidLeverage();
        }

        balance[msg.sender] -= margin;

        uint256 tokens = margin * leverage;
        uint256 entryPrice = currentPrice();

        uint256 liquidationPrice = (entryPrice * (100 + leverage)) / 100;
        uint256 profitPrice = (entryPrice * (100 - leverage)) / 100;
        uint256 shares = Math.sqrt(shortTokens + tokens) - shortShares;

        uint256 totalTokens = shortTokens + tokens;
        uint256 dilution = (tokens * PRECISION) / totalTokens;
        uint256 leverageFee = (dilution * margin) / PRECISION;

        margin -= leverageFee;
        shortProfits += leverageFee;
        shortTokens += tokens;
        shortShares += shares;

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

        emit OpenShort(shorts[msg.sender]);
    }

    function closeShort() public {
        Position storage position = shorts[msg.sender];
        if (!position.active) revert NoActiveShort();

        uint256 _currentPrice = currentPrice();

        if (_currentPrice >= position.liquidation) {
            liquidateShort(msg.sender);
        } else if (_currentPrice > position.entry) {
            closeShortLoss();
        } else {
            closeShortProfit();
        }
    }

    function liquidateShort(address user) internal {
        Position storage position = shorts[user];
        if (!position.active) revert NoActiveShort();

        uint256 _currentPrice = currentPrice();
        if (_currentPrice < position.liquidation) revert NotLiquidatable();

        shortTokens -= position.tokens;
        shortShares -= position.shares;
        longProfits += position.margin;

        emit ShortLiquidated(position);
        delete shorts[user];
    }

    function closeShortLoss() internal {
        Position storage position = shorts[msg.sender];
        if (!position.active) revert NoActiveShort();

        uint256 _currentPrice = currentPrice();

        if (
            _currentPrice <= position.entry ||
            _currentPrice >= position.liquidation
        ) {
            revert NotCloseableAtLoss();
        }

        uint256 lossRatio = ((_currentPrice - position.entry) * PRECISION) /
            (position.liquidation - position.entry);
        uint256 loss = (position.margin * lossRatio) / PRECISION;

        balance[msg.sender] += position.margin - loss;
        longProfits += loss;
        shortTokens -= position.tokens;
        shortShares -= position.shares;

        emit ShortClosedAtLoss(position);
        delete shorts[msg.sender];
    }

    function closeShortProfit() internal {
        Position storage position = shorts[msg.sender];
        if (!position.active) revert NoActiveShort();

        uint256 _currentPrice = currentPrice();
        if (_currentPrice > position.entry) revert NotCloseableAtProfit();

        uint256 profit;
        if (_currentPrice <= position.profit) {
            profit = (position.shares * shortProfits) / shortShares;
        } else {
            uint256 profitRatio = ((_currentPrice - position.profit) *
                PRECISION) / (position.entry - position.profit);
            profit =
                (position.shares * shortProfits * profitRatio) /
                (shortShares * PRECISION);
        }

        balance[msg.sender] += position.margin + profit;
        shortProfits -= profit;
        shortTokens -= position.tokens;
        shortShares -= position.shares;

        emit ShortClosedAtProfit(position);
        delete shorts[msg.sender];
    }
    function openLong(
        uint256 margin,
        uint256 leverage
    ) public sufficientBalance(margin) {
        if (margin < MIN_MARGIN) revert InsufficientMargin();
        if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE) {
            revert InvalidLeverage();
        }

        balance[msg.sender] -= margin;

        uint256 tokens = margin * leverage;
        uint256 entryPrice = currentPrice();

        uint256 liquidationPrice = (entryPrice * (100 - leverage)) / 100;
        uint256 profitPrice = (entryPrice * (100 + leverage)) / 100;
        uint256 shares = Math.sqrt(longTokens + tokens) - longShares;

        uint256 totalTokens = longTokens + tokens;
        uint256 dilution = (tokens * PRECISION) / totalTokens;
        uint256 leverageFee = (dilution * margin) / PRECISION;

        margin -= leverageFee;
        longProfits += leverageFee;
        longTokens += tokens;
        longShares += shares;

        longs[msg.sender] = Position({
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

        emit OpenLong(longs[msg.sender]);
    }

    function closeLong() public {
        Position storage position = longs[msg.sender];
        if (!position.active) revert NoActiveLong();

        uint256 _currentPrice = currentPrice();

        if (_currentPrice <= position.liquidation) {
            liquidateLong(msg.sender);
        } else if (_currentPrice < position.entry) {
            closeLongLoss();
        } else {
            closeLongProfit();
        }
    }

    function liquidateLong(address user) internal {
        Position storage position = longs[user];
        if (!position.active) revert NoActiveLong();

        uint256 _currentPrice = currentPrice();
        if (_currentPrice > position.liquidation) revert NotLiquidatable();

        longTokens -= position.tokens;
        longShares -= position.shares;
        shortProfits += position.margin;

        emit LongLiquidated(position);
        delete longs[user];
    }

    function closeLongLoss() internal {
        Position storage position = longs[msg.sender];
        if (!position.active) revert NoActiveLong();

        uint256 _currentPrice = currentPrice();
        if (
            _currentPrice > position.entry ||
            _currentPrice < position.liquidation
        ) {
            revert NotCloseableAtLoss();
        }

        uint256 lossRatio = ((position.entry - _currentPrice) * PRECISION) /
            (position.entry - position.liquidation);
        uint256 loss = (position.margin * lossRatio) / PRECISION;

        balance[msg.sender] += position.margin - loss;
        shortProfits += loss;
        longTokens -= position.tokens;
        longShares -= position.shares;

        emit LongClosedAtLoss(position);
        delete longs[msg.sender];
    }

    function closeLongProfit() internal {
        Position storage position = longs[msg.sender];
        if (!position.active) revert NoActiveLong();

        uint256 _currentPrice = currentPrice();
        if (_currentPrice < position.entry) revert NotCloseableAtProfit();

        uint256 profit;
        if (_currentPrice >= position.profit) {
            profit = (position.shares * longProfits) / longShares;
        } else {
            uint256 profitRatio = ((_currentPrice - position.entry) *
                PRECISION) / (position.profit - position.entry);
            profit =
                (position.shares * longProfits * profitRatio) /
                (longShares * PRECISION);
        }

        balance[msg.sender] += position.margin + profit;
        longProfits -= profit;
        longTokens -= position.tokens;
        longShares -= position.shares;

        emit LongClosedAtProfit(position);
        delete longs[msg.sender];
    }

    function fundingRateShort(address user) public {
        Position storage position = shorts[user];
        if (!position.active) revert NoActiveShort();
        if (position.funding > block.timestamp) revert FundingRateNotDue();

        if (shortTokens <= longTokens) {
            position.funding += FUNDING_INTERVAL;
            return;
        }

        uint256 totalTokens = shortTokens + longTokens;
        uint256 shortRatio = (shortTokens * 100) / totalTokens;
        uint256 longRatio = 100 - shortRatio;

        uint256 fundingFeePercentage = (shortRatio - longRatio) /
            FUNDING_PERIODS;
        uint256 fundingFee = (position.margin * fundingFeePercentage) / 100;

        if (fundingFee >= position.margin) {
            shortTokens -= position.tokens;
            shortShares -= position.shares;
            longProfits += position.margin;

            emit ShortLiquidated(position);
            delete shorts[user];
        } else {
            position.margin -= fundingFee;
            longProfits += fundingFee;

            position.leverage = (position.tokens * PRECISION) / position.margin;
            position.liquidation =
                (position.entry * (100 + position.leverage)) /
                100;
            position.profit =
                (position.entry * (100 - position.leverage)) /
                100;

            position.funding += FUNDING_INTERVAL;

            emit ShortFundingPaid(position);
        }
    }
    function fundingRateLong(address user) public {
        Position storage position = longs[user];
        if (!position.active) revert NoActiveLong();
        if (position.funding > block.timestamp) revert FundingRateNotDue();

        if (longTokens <= shortTokens) {
            position.funding += FUNDING_INTERVAL;
            return;
        }

        uint256 totalTokens = shortTokens + longTokens;
        uint256 longRatio = (longTokens * 100) / totalTokens;
        uint256 shortRatio = 100 - longRatio;

        uint256 fundingFeePercentage = (longRatio - shortRatio) /
            FUNDING_PERIODS;
        uint256 fundingFee = (position.margin * fundingFeePercentage) / 100;

        if (fundingFee >= position.margin) {
            longTokens -= position.tokens;
            longShares -= position.shares;
            shortProfits += position.margin;

            emit LongLiquidated(position);
            delete longs[user];
        } else {
            position.margin -= fundingFee;
            shortProfits += fundingFee;

            position.leverage = (position.tokens * PRECISION) / position.margin;
            position.liquidation =
                (position.entry * (100 - position.leverage)) /
                100;
            position.profit =
                (position.entry * (100 + position.leverage)) /
                100;

            position.funding += FUNDING_INTERVAL;

            emit LongFundingPaid(position);
        }
    }
    function addMarginShort(
        address user,
        uint256 amount
    ) public sufficientBalance(amount) {
        Position storage position = shorts[user];
        if (!position.active) revert NoActiveShort();

        balance[user] -= amount;
        position.margin += amount;

        position.leverage = (position.tokens * PRECISION) / position.margin;
        position.profit = (position.entry * (100 - position.leverage)) / 100;
        position.liquidation =
            (position.entry * (100 + position.leverage)) /
            100;

        emit MarginAddedShort(position);
    }
    function addMarginLong(
        address user,
        uint256 amount
    ) public sufficientBalance(amount) {
        Position storage position = longs[user];
        if (!position.active) revert NoActiveLong();

        balance[user] -= amount;
        position.margin += amount;

        position.leverage = (position.tokens * PRECISION) / position.margin;
        position.profit = (position.entry * (100 + position.leverage)) / 100;
        position.liquidation =
            (position.entry * (100 - position.leverage)) /
            100;

        emit MarginAddedLong(position);
    }
}
