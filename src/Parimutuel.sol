// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

//    _______     __        _______    __     ___      ___  ____  ____  ___________  ____  ____   _______  ___
//   |   __ "\   /""\      /"      \  |" \   |"  \    /"  |("  _||_ " |("     _   ")("  _||_ " | /"     "||"  |
//   (. |__) :) /    \    |:        | ||  |   \   \  //   ||   (  ) : | )__/  \\__/ |   (  ) : |(: ______)||  |
//   |:  ____/ /' /\  \   |_____/   ) |:  |   /\\  \/.    |(:  |  | . )    \\_ /    (:  |  | . ) \/    |  |:  |
//   (|  /    //  __'  \   //      /  |.  |  |: \.        | \\ \__/ //     |.  |     \\ \__/ //  // ___)_  \  |___
//  /|__/ \  /   /  \\  \ |:  __   \  /\  |\ |.  \    /:  | /\\ __ //\     \:  |     /\\ __ //\ (:      "|( \_|:  \
// (_______)(___/    \___)|__|  \___)(__\_|_)|___|\__/|___|(__________)     \__|    (__________) \_______) \_______)

import {Math} from "./libraries/Math.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

contract Parimutuel is Math {
    address public admin; /// @notice Address of the admin.
    AggregatorV3Interface public priceOracle; /// @notice Price oracle interface.
    IERC20 public settlementToken; /// @notice Settlement token interface.

    uint256 public shortTokens; /// @notice Total short tokens.
    uint256 public longTokens; /// @notice Total long tokens.
    uint256 public shortProfits; /// @notice Total short profits.
    uint256 public longProfits; /// @notice Total long profits.
    uint256 public shortShares; /// @notice Total short shares.
    uint256 public longShares; /// @notice Total long shares.

    mapping(address => uint256) public balance; /// @notice User balances.
    mapping(address => Position) public shorts; /// @notice User short positions.
    mapping(address => Position) public longs; /// @notice User long positions.

    uint256 public constant FUNDING_INTERVAL = 21600; /// @notice Funding interval.
    uint256 public constant FUNDING_PERIODS = 1460; /// @notice Number of funding periods.
    uint256 public constant MIN_LEVERAGE = 1 * PRECISION; /// @notice Minimum leverage.
    uint256 public constant MAX_LEVERAGE = 100 * PRECISION; /// @notice Maximum leverage.
    uint256 public constant PRECISION = 10 ** 18; /// @notice Precision value.
    uint256 public constant MIN_MARGIN = PRECISION; /// @notice Minimum margin.

    //// @notice Structure representing a trading position.
    struct Position {
        bool active; /// @notice Indicates whether the position is active.
        uint256 margin; /// @notice The margin amount for the position.
        uint256 leverage; /// @notice The leverage factor applied to the position.
        uint256 tokens; /// @notice The number of tokens involved in the position.
        uint256 entry; /// @notice The entry price of the position.
        uint256 liquidation; /// @notice The liquidation price of the position.
        uint256 profit; /// @notice The profit price of the position.
        uint256 shares; /// @notice The number of shares associated with the position.
        uint256 funding; /// @notice The next funding timestamp for the position.
    }

    error AmountMustBeGreaterThanZero(); /// @notice Error for zero amount.
    error TransferFailed(); /// @notice Error for failed transfer.
    error InsufficientBalance(); /// @notice Error for insufficient balance.
    error InsufficientMargin(); /// @notice Error for insufficient margin.
    error InvalidLeverage(); /// @notice Error for invalid leverage.
    error NoActiveShort(); /// @notice Error for no active short position.
    error NoActiveLong(); /// @notice Error for no active long position.
    error NotLiquidatable(); /// @notice Error for not being liquidatable.
    error NotCloseableAtLoss(); /// @notice Error for not closeable at loss.
    error NotCloseableAtProfit(); /// @notice Error for not closeable at profit.
    error FundingRateNotDue(); /// @notice Error for funding rate not due.

    event Deposit(address indexed user, uint256 amount); /// @notice Event for deposits.
    event Withdraw(address indexed user, uint256 amount); /// @notice Event for withdrawals.
    event OpenShort(Position indexed short); /// @notice Event for opening short positions.
    event ShortLiquidated(Position indexed short); /// @notice Event for short position liquidation.
    event ShortClosedAtLoss(Position indexed short); /// @notice Event for closing short position at loss.
    event ShortClosedAtProfit(Position indexed short); /// @notice Event for closing short position at profit.
    event OpenLong(Position indexed short); /// @notice Event for opening long positions.
    event LongLiquidated(Position indexed short); /// @notice Event for long position liquidation.
    event LongClosedAtLoss(Position indexed short); /// @notice Event for closing long position at loss.
    event LongClosedAtProfit(Position indexed short); /// @notice Event for closing long position at profit.
    event ShortFundingPaid(Position indexed short); /// @notice Event for paying short funding.
    event LongFundingPaid(Position indexed long); /// @notice Event for paying long funding.
    event MarginAddedShort(Position indexed short); /// @notice Event for adding margin to short position.
    event MarginAddedLong(Position indexed short); /// @notice Event for adding margin to long position.

    /// @notice Constructor to initialize the contract with oracle and settlement token addresses.
    /// @param _priceOracle Address of the price oracle.
    /// @param _settlementToken Address of the settlement token.
    constructor(address _priceOracle, address _settlementToken) {
        priceOracle = AggregatorV3Interface(_priceOracle);
        settlementToken = IERC20(_settlementToken);
        admin = msg.sender;
    }

    /// @notice Modifier to check if the user has sufficient balance.
    /// @param amount The amount to check.
    modifier sufficientBalance(uint256 amount) {
        if (balance[msg.sender] < amount) revert InsufficientBalance();
        _;
    }

    /// @notice Returns the current price from the oracle.
    /// @return The current price.
    function currentPrice() public view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(priceOracle)
            .latestRoundData();
        if (price < 0) price = 0;
        return uint256(price);
    }

    /// @notice Deposit an amount of settlement tokens.
    /// @param amount The amount to deposit.
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

    /// @notice Withdraw an amount of settlement tokens.
    /// @param amount The amount to withdraw.
    function withdraw(uint256 amount) public sufficientBalance(amount) {
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        balance[msg.sender] -= amount;

        bool success = settlementToken.transfer(msg.sender, amount);
        if (!success) revert TransferFailed();

        emit Withdraw(msg.sender, amount);
    }

    /// @notice Open a short position with specified margin and leverage.
    /// @param margin The margin amount.
    /// @param leverage The leverage factor.
    function openShort(
        uint256 margin,
        uint256 leverage
    ) public sufficientBalance(margin) returns (Position memory) {
        if (margin < MIN_MARGIN) revert InsufficientMargin();
        if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE)
            revert InvalidLeverage();

        balance[msg.sender] -= margin;

        uint256 tokens = margin * leverage;
        uint256 entryPrice = currentPrice();
        uint256 liquidationPrice = entryPrice + (entryPrice / leverage);
        uint256 profitPrice = entryPrice - (entryPrice / leverage);
        uint256 shares = Math.sqrt(shortTokens + tokens) - shortShares;

        uint256 leverageFee = 0;
        uint256 adjustedMargin = margin;

        if (shortTokens > 0) {
            uint256 totalTokens = shortTokens + tokens;
            uint256 dilution = (tokens * PRECISION) / totalTokens;
            leverageFee = (dilution * margin) / PRECISION;
            adjustedMargin = margin - leverageFee;
        }

        if (adjustedMargin == 0) revert InsufficientMargin();

        shortProfits += leverageFee;
        shortTokens += tokens;
        shortShares += shares;

        shorts[msg.sender] = Position({
            active: true,
            margin: adjustedMargin,
            leverage: leverage,
            tokens: tokens,
            entry: entryPrice,
            liquidation: liquidationPrice,
            profit: profitPrice,
            shares: shares,
            funding: block.timestamp + FUNDING_INTERVAL
        });

        emit OpenShort(shorts[msg.sender]);
        return shorts[msg.sender];
    }

    /// @notice Close the short position of the caller.
    function closeShort() public returns (Position memory) {
        Position storage position = shorts[msg.sender];
        if (!position.active) revert NoActiveShort();

        uint256 _currentPrice = currentPrice();

        if (_currentPrice >= position.liquidation) {
            return liquidateShort(msg.sender);
        } else if (_currentPrice > position.entry) {
            return closeShortLoss();
        } else {
            return closeShortProfit();
        }
    }

    /// @notice Liquidate the short position of a user.
    /// @param user The address of the user.
    function liquidateShort(address user) public returns (Position memory) {
        Position storage position = shorts[user];
        if (!position.active) revert NoActiveShort();

        uint256 _currentPrice = currentPrice();
        if (_currentPrice < position.liquidation) revert NotLiquidatable();

        shortTokens -= position.tokens;
        shortShares -= position.shares;
        longProfits += position.margin;

        emit ShortLiquidated(position);
        delete shorts[user];
        return shorts[user];
    }

    /// @notice Close the short position at a loss.
    function closeShortLoss() public returns (Position memory) {
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
        return shorts[msg.sender];
    }

    /// @notice Close the short position at a profit.
    function closeShortProfit() public returns (Position memory) {
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

        uint256 netProfit = (profit * 99) / 100;
        uint256 fee = profit - netProfit;

        balance[admin] += fee;
        balance[msg.sender] += position.margin + netProfit;

        shortProfits -= profit;
        shortTokens -= position.tokens;
        shortShares -= position.shares;

        emit ShortClosedAtProfit(position);
        delete shorts[msg.sender];
        return shorts[msg.sender];
    }

    /// @notice Open a long position with specified margin and leverage.
    /// @param margin The margin amount.
    /// @param leverage The leverage factor.
    function openLong(
        uint256 margin,
        uint256 leverage
    ) public sufficientBalance(margin) returns (Position memory) {
        if (margin < MIN_MARGIN) revert InsufficientMargin();
        if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE)
            revert InvalidLeverage();

        balance[msg.sender] -= margin;

        uint256 tokens = margin * leverage;
        uint256 entryPrice = currentPrice();
        uint256 liquidationPrice = entryPrice - (entryPrice / leverage);
        uint256 profitPrice = entryPrice + (entryPrice / leverage);
        uint256 shares = Math.sqrt(longTokens + tokens) - longShares;

        uint256 leverageFee = 0;
        uint256 adjustedMargin = margin;

        if (longTokens > 0) {
            uint256 totalTokens = longTokens + tokens;
            uint256 dilution = (tokens * PRECISION) / totalTokens;
            leverageFee = (dilution * margin) / PRECISION;
            adjustedMargin = margin - leverageFee;
        }

        if (adjustedMargin == 0) revert InsufficientMargin();

        longProfits += leverageFee;
        longTokens += tokens;
        longShares += shares;

        longs[msg.sender] = Position({
            active: true,
            margin: adjustedMargin,
            leverage: leverage,
            tokens: tokens,
            entry: entryPrice,
            liquidation: liquidationPrice,
            profit: profitPrice,
            shares: shares,
            funding: block.timestamp + FUNDING_INTERVAL
        });

        emit OpenLong(longs[msg.sender]);
        return longs[msg.sender];
    }

    function closeLong() public returns (Position memory) {
        Position storage position = longs[msg.sender];
        if (!position.active) revert NoActiveLong();

        uint256 _currentPrice = currentPrice();

        if (_currentPrice <= position.liquidation) {
            return liquidateLong(msg.sender);
        } else if (_currentPrice < position.entry) {
            return closeLongLoss();
        } else {
            return closeLongProfit();
        }
    }

    /// @notice Liquidate the long position of a user.
    /// @param user The address of the user.
    function liquidateLong(address user) public returns (Position memory) {
        Position storage position = longs[user];
        if (!position.active) revert NoActiveLong();

        uint256 _currentPrice = currentPrice();
        if (_currentPrice > position.liquidation) revert NotLiquidatable();

        longTokens -= position.tokens;
        longShares -= position.shares;
        shortProfits += position.margin;

        emit LongLiquidated(position);
        delete longs[user];
        return longs[user];
    }

    /// @notice Close the long position at a loss.
    function closeLongLoss() public returns (Position memory) {
        Position storage position = longs[msg.sender];
        if (!position.active) revert NoActiveLong();

        uint256 _currentPrice = currentPrice();

        if (
            _currentPrice >= position.entry ||
            _currentPrice <= position.liquidation
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
        return longs[msg.sender];
    }

    /// @notice Close the long position at a profit.
    function closeLongProfit() public returns (Position memory) {
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

        uint256 netProfit = (profit * 99) / 100;
        uint256 fee = profit - netProfit;

        balance[admin] += fee;
        balance[msg.sender] += position.margin + netProfit;

        longProfits -= profit;
        longTokens -= position.tokens;
        longShares -= position.shares;

        emit LongClosedAtProfit(position);
        delete longs[msg.sender];
        return longs[msg.sender];
    }

    /// @notice Update the funding rate for a short position.
    /// @param user The address of the user.
    function fundingRateShort(address user) public returns (Position memory) {
        Position storage position = shorts[user];
        if (!position.active) revert NoActiveShort();
        if (position.funding > block.timestamp) revert FundingRateNotDue();
        if (shortTokens <= longTokens) {
            position.funding += FUNDING_INTERVAL;
            return shorts[user];
        }

        uint256 totalTokens = shortTokens + longTokens;
        uint256 difference = shortTokens - longTokens;
        uint256 fundingFee = (position.margin * difference) / totalTokens;

        if (fundingFee >= position.margin) {
            shortTokens -= position.tokens;
            shortShares -= position.shares;
            longProfits += position.margin;

            emit ShortLiquidated(position);
            delete shorts[user];
            return shorts[user];
        }

        position.margin -= fundingFee;
        longProfits += fundingFee;
        position.leverage = position.tokens / position.margin;
        position.liquidation =
            (position.entry * ((100 * PRECISION) + position.leverage)) /
            100;
        position.profit =
            (position.entry * ((100 * PRECISION) - position.leverage)) /
            100;
        position.funding += FUNDING_INTERVAL;

        emit ShortFundingPaid(position);
        return shorts[user];
    }

    /// @notice Update the funding rate for a long position.
    /// @param user The address of the user.
    function fundingRateLong(address user) public returns (Position memory) {
        Position storage position = longs[user];
        if (!position.active) revert NoActiveLong();
        if (position.funding > block.timestamp) revert FundingRateNotDue();
        if (longTokens <= shortTokens) {
            position.funding += FUNDING_INTERVAL;
            return longs[user];
        }

        uint256 totalTokens = shortTokens + longTokens;
        uint256 difference = longTokens - shortTokens;
        uint256 fundingFee = (position.margin * difference) / totalTokens;

        if (fundingFee >= position.margin) {
            longTokens -= position.tokens;
            longShares -= position.shares;
            shortProfits += position.margin;

            emit LongLiquidated(position);
            delete longs[user];
            return longs[user];
        }

        position.margin -= fundingFee;
        shortProfits += fundingFee;
        position.leverage = position.tokens / position.margin;
        position.liquidation =
            (position.entry * ((100 * PRECISION) - position.leverage)) /
            100;
        position.profit =
            (position.entry * ((100 * PRECISION) + position.leverage)) /
            100;
        position.funding += FUNDING_INTERVAL;

        emit LongFundingPaid(position);
        return longs[user];
    }

    /// @notice Add margin to a short position.
    /// @param user The address of the user.
    /// @param amount The amount to add.
    function addMarginShort(
        address user,
        uint256 amount
    ) public sufficientBalance(amount) returns (Position memory) {
        Position storage position = shorts[user];
        if (!position.active) revert NoActiveShort();

        balance[user] -= amount;
        position.margin += amount;

        position.leverage = position.tokens / position.margin;
        position.profit =
            (position.entry * ((100 * PRECISION) - position.leverage)) /
            100;
        position.liquidation =
            (position.entry * ((100 * PRECISION) + position.leverage)) /
            100;

        emit MarginAddedShort(position);
        return shorts[msg.sender];
    }

    /// @notice Add margin to a long position.
    /// @param user The address of the user.
    /// @param amount The amount to add.
    function addMarginLong(
        address user,
        uint256 amount
    ) public sufficientBalance(amount) returns (Position memory) {
        Position storage position = longs[user];
        if (!position.active) revert NoActiveLong();

        balance[user] -= amount;
        position.margin += amount;

        position.leverage = position.tokens / position.margin;
        position.profit =
            (position.entry * ((100 * PRECISION) + position.leverage)) /
            100;
        position.liquidation =
            (position.entry * ((100 * PRECISION) - position.leverage)) /
            100;

        emit MarginAddedLong(position);
        return longs[msg.sender];
    }
}
