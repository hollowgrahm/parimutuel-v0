// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

//    _______     __        _______    __     ___      ___  ____  ____  ___________  ____  ____   _______  ___
//   |   __ "\   /""\      /"      \  |" \   |"  \    /"  |("  _||_ " |("     _   ")("  _||_ " | /"     "||"  |
//   (. |__) :) /    \    |:        | ||  |   \   \  //   ||   (  ) : | )__/  \\__/ |   (  ) : |(: ______)||  |
//   |:  ____/ /' /\  \   |_____/   ) |:  |   /\\  \/.    |(:  |  | . )    \\_ /    (:  |  | . ) \/    |  |:  |
//   (|  /    //  __'  \   //      /  |.  |  |: \.        | \\ \__/ //     |.  |     \\ \__/ //  // ___)_  \  |___
//  /|__/ \  /   /  \\  \ |:  __   \  /\  |\ |.  \    /:  | /\\ __ //\     \:  |     /\\ __ //\ (:      "|( \_|:  \
// (_______)(___/    \___)|__|  \___)(__\_|_)|___|\__/|___|(__________)     \__|    (__________) \_______) \_______)

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

    enum Direction {
        Short,
        Long
    }

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
    error NoActivePosition(Direction direction);
    error NotLiquidatable();
    error NotCloseableAtLoss();
    error NotCloseableAtProfit();
    error FundingRateNotDue();

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event OpenPosition(Position indexed position, Direction direction);
    event FundingPaid(Position indexed position, Direction direction);
    event MarginAdded(Position indexed position, Direction direction);
    event PositionLiquidated(Position indexed position, Direction direction);
    event PositionClosedAtLoss(Position indexed position, Direction direction);
    event PositionClosedAtProfit(
        Position indexed position,
        Direction direction
    );

    /// @notice Constructor initializes the contract with the price oracle and settlement token addresses.
    /// @param _priceOracle Address of the price oracle contract.
    /// @param _settlementToken Address of the settlement token contract.
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

    /// @notice Returns the current price from the price oracle.
    /// @return The current price as a uint256.
    function currentPrice() public view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(priceOracle)
            .latestRoundData();
        if (price < 0) price = 0;
        return uint256(price);
    }

    /// @notice Deposits a specified amount of settlement tokens into the contract.
    /// @param amount The amount of tokens to deposit.
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

    /// @notice Withdraws a specified amount of settlement tokens from the contract.
    /// @param amount The amount of tokens to withdraw.
    function withdraw(uint256 amount) public sufficientBalance(amount) {
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        balance[msg.sender] -= amount;

        bool success = settlementToken.transfer(msg.sender, amount);
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, amount);
    }

    /// @notice Opens a new position (short or long) with the specified margin and leverage.
    /// @param margin The margin amount for the position.
    /// @param leverage The leverage for the position.
    /// @param direction The direction of the position (short or long).
    function openPosition(
        uint256 margin,
        uint256 leverage,
        Direction direction
    ) public sufficientBalance(margin) {
        if (margin < MIN_MARGIN) revert InsufficientMargin();
        if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE) {
            revert InvalidLeverage();
        }

        balance[msg.sender] -= margin;

        uint256 tokens = margin * leverage;
        uint256 entryPrice = currentPrice();

        uint256 liquidationPrice = direction == Direction.Short
            ? (entryPrice * (100 + leverage)) / 100
            : (entryPrice * (100 - leverage)) / 100;
        uint256 profitPrice = direction == Direction.Short
            ? (entryPrice * (100 - leverage)) / 100
            : (entryPrice * (100 + leverage)) / 100;
        uint256 shares = Math.sqrt(
            direction == Direction.Short
                ? shortTokens + tokens
                : longTokens + tokens
        ) - (direction == Direction.Short ? shortShares : longShares);

        uint256 totalTokens = direction == Direction.Short
            ? shortTokens + tokens
            : longTokens + tokens;
        uint256 dilution = (tokens * PRECISION) / totalTokens;
        uint256 leverageFee = (dilution * margin) / PRECISION;

        margin -= leverageFee;
        if (direction == Direction.Short) {
            shortProfits += leverageFee;
            shortTokens += tokens;
            shortShares += shares;
        } else {
            longProfits += leverageFee;
            longTokens += tokens;
            longShares += shares;
        }

        Position storage position = direction == Direction.Short
            ? shorts[msg.sender]
            : longs[msg.sender];
        position.active = true;
        position.margin = margin;
        position.leverage = leverage;
        position.tokens = tokens;
        position.entry = entryPrice;
        position.liquidation = liquidationPrice;
        position.profit = profitPrice;
        position.shares = shares;
        position.funding = block.timestamp + FUNDING_INTERVAL;

        emit OpenPosition(position, direction);
    }

    /// @notice Closes the position (short or long) for the sender.
    /// @param direction The direction of the position to close.
    function closePosition(Direction direction) public {
        Position storage position = direction == Direction.Short
            ? shorts[msg.sender]
            : longs[msg.sender];
        if (!position.active) {
            revert NoActivePosition(direction);
        }

        uint256 _currentPrice = currentPrice();

        if (
            (direction == Direction.Short &&
                _currentPrice >= position.liquidation) ||
            (direction == Direction.Long &&
                _currentPrice <= position.liquidation)
        ) {
            liquidatePosition(msg.sender, direction);
        } else if (
            (direction == Direction.Short && _currentPrice > position.entry) ||
            (direction == Direction.Long && _currentPrice < position.entry)
        ) {
            closePositionLoss(direction);
        } else {
            closePositionProfit(direction);
        }
    }

    /// @notice Liquidates the position (short or long) for the specified user.
    /// @param user The address of the user whose position is to be liquidated.
    /// @param direction The direction of the position to liquidate.
    function liquidatePosition(address user, Direction direction) public {
        Position storage position = direction == Direction.Short
            ? shorts[user]
            : longs[user];
        if (!position.active) {
            revert NoActivePosition(direction);
        }

        uint256 _currentPrice = currentPrice();
        if (
            (direction == Direction.Short &&
                _currentPrice < position.liquidation) ||
            (direction == Direction.Long &&
                _currentPrice > position.liquidation)
        ) revert NotLiquidatable();

        if (direction == Direction.Short) {
            shortTokens -= position.tokens;
            shortShares -= position.shares;
            longProfits += position.margin;
        } else {
            longTokens -= position.tokens;
            longShares -= position.shares;
            shortProfits += position.margin;
        }

        emit PositionLiquidated(position, direction);
        resetPosition(position);
    }

    /// @notice Closes the position at a loss for the sender.
    /// @param direction The direction of the position to close.
    function closePositionLoss(Direction direction) internal {
        Position storage position = direction == Direction.Short
            ? shorts[msg.sender]
            : longs[msg.sender];
        if (!position.active) {
            revert NoActivePosition(direction);
        }

        uint256 _currentPrice = currentPrice();

        if (
            (direction == Direction.Short &&
                (_currentPrice <= position.entry ||
                    _currentPrice >= position.liquidation)) ||
            (direction == Direction.Long &&
                (_currentPrice >= position.entry ||
                    _currentPrice <= position.liquidation))
        ) {
            revert NotCloseableAtLoss();
        }

        uint256 lossRatio = direction == Direction.Short
            ? ((_currentPrice - position.entry) * PRECISION) /
                (position.liquidation - position.entry)
            : ((position.entry - _currentPrice) * PRECISION) /
                (position.entry - position.liquidation);
        uint256 loss = (position.margin * lossRatio) / PRECISION;

        balance[msg.sender] += position.margin - loss;
        if (direction == Direction.Short) {
            longProfits += loss;
            shortTokens -= position.tokens;
            shortShares -= position.shares;
        } else {
            shortProfits += loss;
            longTokens -= position.tokens;
            longShares -= position.shares;
        }

        emit PositionClosedAtLoss(position, direction);
        resetPosition(position);
    }

    /// @notice Closes the position at a profit for the sender.
    /// @param direction The direction of the position to close.
    function closePositionProfit(Direction direction) internal {
        Position storage position = direction == Direction.Short
            ? shorts[msg.sender]
            : longs[msg.sender];
        if (!position.active) {
            revert NoActivePosition(direction);
        }

        uint256 _currentPrice = currentPrice();
        if (
            (direction == Direction.Short && _currentPrice > position.entry) ||
            (direction == Direction.Long && _currentPrice < position.entry)
        ) revert NotCloseableAtProfit();

        uint256 profit;
        if (
            (direction == Direction.Short &&
                _currentPrice <= position.profit) ||
            (direction == Direction.Long && _currentPrice >= position.profit)
        ) {
            profit =
                (position.shares *
                    (
                        direction == Direction.Short
                            ? shortProfits
                            : longProfits
                    )) /
                (direction == Direction.Short ? shortShares : longShares);
        } else {
            uint256 profitRatio = direction == Direction.Short
                ? ((_currentPrice - position.profit) * PRECISION) /
                    (position.entry - position.profit)
                : ((_currentPrice - position.entry) * PRECISION) /
                    (position.profit - position.entry);
            profit =
                (position.shares *
                    (
                        direction == Direction.Short
                            ? shortProfits
                            : longProfits
                    ) *
                    profitRatio) /
                ((direction == Direction.Short ? shortShares : longShares) *
                    PRECISION);
        }

        balance[msg.sender] += position.margin + profit;
        if (direction == Direction.Short) {
            shortProfits -= profit;
            shortTokens -= position.tokens;
            shortShares -= position.shares;
        } else {
            longProfits -= profit;
            longTokens -= position.tokens;
            longShares -= position.shares;
        }

        emit PositionClosedAtProfit(position, direction);
        resetPosition(position);
    }

    /// @notice Pays the funding rate for the specified user's position.
    /// @param user The address of the user whose funding rate is to be paid.
    /// @param direction The direction of the position.
    function fundingRate(address user, Direction direction) public {
        Position storage position = direction == Direction.Short
            ? shorts[user]
            : longs[user];
        if (!position.active) {
            revert NoActivePosition(direction);
        }
        if (position.funding > block.timestamp) revert FundingRateNotDue();

        if (
            (direction == Direction.Short && shortTokens <= longTokens) ||
            (direction == Direction.Long && longTokens <= shortTokens)
        ) {
            position.funding += FUNDING_INTERVAL;
            return;
        }

        uint256 totalTokens = shortTokens + longTokens;
        uint256 shortRatio = (shortTokens * 100) / totalTokens;
        uint256 longRatio = 100 - shortRatio;

        uint256 fundingFeePercentage = direction == Direction.Short
            ? (shortRatio - longRatio) / FUNDING_PERIODS
            : (longRatio - shortRatio) / FUNDING_PERIODS;
        uint256 fundingFee = (position.margin * fundingFeePercentage) / 100;

        if (fundingFee >= position.margin) {
            if (direction == Direction.Short) {
                shortTokens -= position.tokens;
                shortShares -= position.shares;
                longProfits += position.margin;
            } else {
                longTokens -= position.tokens;
                longShares -= position.shares;
                shortProfits += position.margin;
            }

            emit PositionLiquidated(position, direction);
            resetPosition(position);
        } else {
            position.margin -= fundingFee;
            if (direction == Direction.Short) {
                longProfits += fundingFee;
            } else {
                shortProfits += fundingFee;
            }

            position.leverage = (position.tokens * PRECISION) / position.margin;
            position.liquidation = direction == Direction.Short
                ? (position.entry * (100 + position.leverage)) / 100
                : (position.entry * (100 - position.leverage)) / 100;
            position.profit = direction == Direction.Short
                ? (position.entry * (100 - position.leverage)) / 100
                : (position.entry * (100 + position.leverage)) / 100;

            position.funding += FUNDING_INTERVAL;

            emit FundingPaid(position, direction);
        }
    }

    /// @notice Adds margin to the specified user's position.
    /// @param user The address of the user whose margin is to be added.
    /// @param amount The amount of margin to add.
    /// @param direction The direction of the position.
    function addMargin(
        address user,
        uint256 amount,
        Direction direction
    ) public sufficientBalance(amount) {
        Position storage position = direction == Direction.Short
            ? shorts[user]
            : longs[user];
        if (!position.active) {
            revert NoActivePosition(direction);
        }

        balance[user] -= amount;
        position.margin += amount;

        position.leverage = (position.tokens * PRECISION) / position.margin;
        position.profit = direction == Direction.Short
            ? (position.entry * (100 - position.leverage)) / 100
            : (position.entry * (100 + position.leverage)) / 100;
        position.liquidation = direction == Direction.Short
            ? (position.entry * (100 + position.leverage)) / 100
            : (position.entry * (100 - position.leverage)) / 100;

        emit MarginAdded(position, direction);
    }

    /// @notice Resets the specified position.
    /// @param position The position to reset.
    function resetPosition(Position storage position) internal {
        position.active = false;
        position.margin = 0;
        position.leverage = 0;
        position.tokens = 0;
        position.entry = 0;
        position.liquidation = 0;
        position.profit = 0;
        position.shares = 0;
        position.funding = 0;
    }
}
