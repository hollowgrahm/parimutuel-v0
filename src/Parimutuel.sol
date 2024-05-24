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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Parimutuel is Math {
    /* ========== STATE VARIABLES ========== */

    address private admin; // Parimutuel Market deployer address
    address private priceOracle; // Chainlink AggregatorV3Interface price feed
    address private settlementToken; // ERC20 token used as the asset for settlement

    uint256 public shortTokens; // Cumulative size of open short positions
    uint256 public longTokens; // Cumulative size of open long positions
    uint256 public shortProfits; // Accumulated profits due to short positions
    uint256 public longProfits; // Accumulated profits due to long positions
    uint256 public shortShares; // Short share ownership of short profits
    uint256 public longShares; // Long share ownership of long profits

    mapping(address => uint256) public balance; // Amount of settlement tokens deposited by a specific user
    mapping(address => Position) public shorts; // Mapping of short positions to addresses
    mapping(address => Position) public longs; // Mapping of long positions to addresses

    uint256 public constant FUNDING_INTERVAL = 21600; // In seconds, 6 hours (60 * 60 * 6)
    uint256 public constant FUNDING_PERIODS = 1460; // In a year, 1460 (365 * 4) ie every six hours
    uint256 public constant MIN_LEVERAGE = 1; // Minimum amount of leverage / position size multiplier
    uint256 public constant MAX_LEVERAGE = 100; // Maximum amount of leverage / position size multiplier
    uint256 public constant PRECISION = 10 ** 18; // Used for precision when emulating fixed point arithmetic with integers
    uint256 public constant MIN_MARGIN = PRECISION;

    struct Position {
        bool active; // Denominates whether position exists
        uint256 margin; // Amount collateralized to open a position
        uint256 leverage; // Multiplier on margin to increase leverage
        uint256 tokens; // Result of margin multiplied by leverage
        uint256 entry; // Curent Price at position inception
        uint256 liquidation; // Liquidation threshold
        uint256 profit; // Profit threshold used to prevent syphoning
        uint256 shares; // Profit shares owned by position
        uint256 funding; // Timestamp when funding rate is due
    }

    /* ========== EVENTS ========== */

    event Opened(Position indexed position);
    event ClosedProfit(Position indexed position);
    event ClosedLoss(Position indexed position);
    event Liquidated(Position indexed position);
    event MarginAdded(Position indexed position);
    event FundingPaid(Position indexed position);

    /* ========== ERRORS ========== */

    error NotEnoughFunds();
    error DepositFailed();
    error WithdrawalFailed();
    error LeverageNotAllowed();
    error ShortAlreadyOpen();
    error LongAlreadyOpen();
    error NoOpenPosition();
    error NotLiquidatable();
    error FundingNotDue();

    /* ========== CONSTRUCTOR ========== */

    constructor(address _priceOracle, address _settlementToken) {
        /// @notice Constructor function when deploying contract
        /// @param  _marketOracle: Address of Chainlink Oracle price feed
        /// @param  _settlementToken: Address of ERC20 token to be used as settlement asset

        admin = msg.sender;
        priceOracle = _priceOracle;
        settlementToken = _settlementToken;
    }

    /* ========== MODIFIERS ========== */

    modifier enoughFunds(uint256 amount) {
        /// @notice Checks that the user has enough funds already deposited
        /// @param  amount: Amount to check

        if (balance[msg.sender] < amount) revert NotEnoughFunds();
        if (amount < MIN_MARGIN) revert NotEnoughFunds();
        _;
    }

    /* ========== FUNCTIONS ========== */

    function currentPrice() public view returns (uint256) {
        /// @notice Chainlink AggregatorV3Interface price feed
        /// @return price: Latest asset price as uint256

        (, int256 price,,,) = AggregatorV3Interface(priceOracle).latestRoundData();
        if (price < 0) price = 0;
        return uint256(price);
    }

    // function userDeposit(uint256 amount) external {
    //     /// @notice User deposit of margin settlement asset
    //     /// @param  amount: Number of settlement token  to be deposited

    //     bool deposit = IERC20(settlementToken).transferFrom(msg.sender, address(this), amount);
    //     if (deposit) balance[msg.sender] += amount;
    //     else revert DepositFailed();
    // }

    // function userWithdrawal(uint256 amount) external enoughFunds(amount) {
    //     /// @notice User deposit of margin settlement asset
    //     /// @param  amount: Number of settlement tokens to be withdrawn

    //     balance[msg.sender] -= amount;
    //     bool withdrawal = IERC20(settlementToken).transfer(msg.sender, amount);
    //     if (!withdrawal) revert WithdrawalFailed();
    // }

    function faucet() external {
        balance[msg.sender] += 1000 * PRECISION;
    }

    function openShort(uint256 _margin, uint256 _leverage) external enoughFunds(_margin) returns (Position memory) {
        /// @notice Opens a short position
        /// @param  _margin: Amount of settlement tokens to collateralize position
        /// @param  _leverage: Multiplier on position size to increase exposure
        /// @return Position that was opened

        if (_leverage < MIN_LEVERAGE || _leverage > MAX_LEVERAGE) revert LeverageNotAllowed();
        if (shorts[msg.sender].active == true) revert ShortAlreadyOpen();

        uint256 _tokens = _margin * _leverage;
        uint256 _dilutedShorts = shortTokens + _tokens;
        uint256 _dilutionRatio = _tokens * PRECISION / _dilutedShorts;
        uint256 _leverageFee = _margin * _dilutionRatio / PRECISION;
        uint256 _updatedMargin = _margin - _leverageFee;

        uint256 _entry = currentPrice();
        uint256 _liquidation = _entry + (_entry / _leverage);
        uint256 _profit = _entry - (_entry / _leverage);
        uint256 _shares = Math.sqrt(shortTokens + _tokens) - shortShares;
        uint256 _funding = block.timestamp + FUNDING_INTERVAL;

        balance[msg.sender] -= _margin;
        shortTokens += _tokens;
        shortShares += _shares;

        shorts[msg.sender] = Position({
            active: true,
            margin: _updatedMargin,
            leverage: _leverage,
            tokens: _tokens,
            entry: _entry,
            liquidation: _liquidation,
            profit: _profit,
            shares: _shares,
            funding: _funding
        });

        emit Opened(shorts[msg.sender]);
        return shorts[msg.sender];
    }

    function closeShort() external {
        /// @notice Wrapper function to close short position

        if (shorts[msg.sender].active == false) revert NoOpenPosition();

        uint256 _currentPrice = currentPrice();

        if (_currentPrice >= shorts[msg.sender].liquidation) {
            liquidatePosition(msg.sender);
        } else if (_currentPrice < shorts[msg.sender].entry) {
            if (_currentPrice <= shorts[msg.sender].profit) _closeShortAboveProfit();
            else _closeShortBelowProfit(_currentPrice);
        } else {
            _closeShortLoss(_currentPrice);
        }
    }

    function _closeShortAboveProfit() internal returns (Position memory) {
        /// @notice  Closes a short position above profit threshold
        /// @dev     Charges 0.5% protocol fee on profits
        /// @return  Position that was closed

        uint256 _profitRatio = shorts[msg.sender].shares * PRECISION / shortShares;
        uint256 _profits = shortProfits * _profitRatio / PRECISION;
        uint256 _profitsAfterFees = _profits * 995 / 1000;
        uint256 _feesPaid = _profits - _profitsAfterFees;

        shortProfits -= _profits;
        shortTokens -= shorts[msg.sender].tokens;
        shortShares -= shorts[msg.sender].shares;
        balance[msg.sender] += shorts[msg.sender].margin + _profitsAfterFees;
        balance[admin] += _feesPaid;

        delete shorts[msg.sender];
        emit ClosedProfit(shorts[msg.sender]);
        return shorts[msg.sender];
    }

    function _closeShortBelowProfit(uint256 _currentPrice) internal returns (Position memory) {
        /// @notice  Closes a short position below profit threshold
        /// @param   _currentPrice: current price calculated in previous function
        /// @dev     Charges 0.5% protocol fee on profits
        /// @return  Position that was closed

        uint256 _entry = shorts[msg.sender].entry;
        uint256 _ratioNumerator = _entry - _currentPrice;
        uint256 _ratioDenominator = _entry - shorts[msg.sender].profit;
        uint256 _effectiveShares = shorts[msg.sender].shares * _ratioNumerator / _ratioDenominator;
        uint256 _profitRatio = _effectiveShares * PRECISION / shortShares;
        uint256 _profits = shortProfits * _profitRatio / PRECISION;
        uint256 _profitsAfterFees = _profits * 995 / 1000;
        uint256 _feesPaid = _profits - _profitsAfterFees;

        shortProfits -= _profits;
        shortTokens -= shorts[msg.sender].tokens;
        shortShares -= shorts[msg.sender].shares;
        balance[msg.sender] += shorts[msg.sender].margin + _profitsAfterFees;
        balance[admin] += _feesPaid;

        delete shorts[msg.sender];
        emit ClosedProfit(shorts[msg.sender]);
        return shorts[msg.sender];
    }

    function _closeShortLoss(uint256 _currentPrice) internal returns (Position memory) {
        /// @notice  Closes a short position at a loss
        /// @param   _currentPrice: current price calculated in previous function
        /// @dev     Does not charge fees on losses

        uint256 _liquidation = shorts[msg.sender].liquidation;
        uint256 _ratioNumerator = _liquidation - _currentPrice;
        uint256 _ratioDenominator = _liquidation - shorts[msg.sender].entry;
        uint256 _redeemableBalance = shorts[msg.sender].margin * _ratioNumerator / _ratioDenominator;

        shorts[msg.sender].margin -= _redeemableBalance;
        balance[msg.sender] += _redeemableBalance;
        longProfits += shorts[msg.sender].margin;
        shortTokens -= shorts[msg.sender].tokens;
        shortShares -= shorts[msg.sender].shares;

        delete shorts[msg.sender];
        emit ClosedLoss(shorts[msg.sender]);
        return shorts[msg.sender];
    }

    function openLong(uint256 _margin, uint256 _leverage) external enoughFunds(_margin) returns (Position memory) {
        /// @notice  Opens a long position
        /// @param   _margin: Number of settlement tokens to collateralize position
        /// @param   _leverage: Multiplier on position size to increase exposure
        /// @return Position that was opened

        if (_leverage < MIN_LEVERAGE || _leverage > MAX_LEVERAGE) revert LeverageNotAllowed();
        if (longs[msg.sender].active == true) revert LongAlreadyOpen();

        uint256 _entry = currentPrice();
        uint256 _liquidation = _entry - (_entry / _leverage);
        uint256 _profit = _entry + (_entry / _leverage);
        uint256 _tokens = _margin * _leverage;
        uint256 _shares = Math.sqrt(longTokens + _tokens) - longShares;
        uint256 _funding = block.timestamp + FUNDING_INTERVAL;

        balance[msg.sender] -= _margin;
        longTokens += _tokens;
        longShares += _shares;

        longs[msg.sender] = Position({
            active: true,
            margin: _margin,
            leverage: _leverage,
            tokens: _tokens,
            entry: _entry,
            liquidation: _liquidation,
            profit: _profit,
            shares: _shares,
            funding: _funding
        });

        emit Opened(longs[msg.sender]);
        return longs[msg.sender];
    }

    function closeLong() external {
        /// @notice Wrapper function to close long position

        if (longs[msg.sender].active == false) revert NoOpenPosition();

        uint256 _currentPrice = currentPrice();

        if (_currentPrice <= longs[msg.sender].liquidation) {
            liquidatePosition(msg.sender);
        } else if (_currentPrice > longs[msg.sender].entry) {
            if (_currentPrice >= longs[msg.sender].profit) _closeLongAboveProfit();
            else _closeLongBelowProfit(_currentPrice);
        } else {
            _closeLongLoss(_currentPrice);
        }
    }

    function _closeLongAboveProfit() internal returns (Position memory) {
        /// @notice  Closes a long position above profit threshold
        /// @dev     Charges 0.5% protocol fee on profits
        /// @return  Position that was closed

        uint256 _profitRatio = longs[msg.sender].shares * PRECISION / longShares;
        uint256 _profits = longProfits * _profitRatio / PRECISION;
        uint256 _profitsAfterFees = _profits * 995 / 1000;
        uint256 _feesPaid = _profits - _profitsAfterFees;

        longProfits -= _profits;
        longTokens -= longs[msg.sender].tokens;
        longShares -= longs[msg.sender].shares;
        balance[msg.sender] += longs[msg.sender].margin + _profitsAfterFees;
        balance[admin] += _feesPaid;

        delete longs[msg.sender];
        emit ClosedProfit(longs[msg.sender]);
        return longs[msg.sender];
    }

    function _closeLongBelowProfit(uint256 _currentPrice) internal returns (Position memory) {
        /// @notice  Closes a long position below profit threshold
        /// @param   _currentPrice: current price calculated in previous function
        /// @dev     Charges 0.5% protocol fee on profits
        /// @return  Position that was closed

        uint256 _entry = longs[msg.sender].entry;
        uint256 _ratioNumerator = _currentPrice - _entry;
        uint256 _ratioDenominator = longs[msg.sender].profit - _entry;
        uint256 _effectiveShares = longs[msg.sender].shares * _ratioNumerator / _ratioDenominator;
        uint256 _profitRatio = _effectiveShares * PRECISION / longShares;
        uint256 _profits = longProfits * _profitRatio / PRECISION;
        uint256 _profitsAfterFees = _profits * 995 / 1000;
        uint256 _feesPaid = _profits - _profitsAfterFees;

        longProfits -= _profits;
        longTokens -= longs[msg.sender].tokens;
        longShares -= longs[msg.sender].shares;
        balance[msg.sender] += longs[msg.sender].margin + _profitsAfterFees;
        balance[admin] += _feesPaid;

        delete longs[msg.sender];
        emit ClosedProfit(longs[msg.sender]);
        return longs[msg.sender];
    }

    function _closeLongLoss(uint256 _currentPrice) internal returns (Position memory) {
        /// @notice  Closes a long position at a loss
        /// @param   _currentPrice: current price calculated in previous function
        /// @dev     Does not charge fees on losses

        uint256 _liquidation = longs[msg.sender].liquidation;
        uint256 _ratioNumerator = _currentPrice - _liquidation;
        uint256 _ratioDenominator = longs[msg.sender].entry - _liquidation;
        // uint256 _redeemableRatio = _currentPrice - _liquidation * PRECISION / longs[msg.sender].entry - _liquidation;
        uint256 _redeemableBalance = longs[msg.sender].margin * _ratioNumerator / _ratioDenominator;

        longs[msg.sender].margin -= _redeemableBalance;
        balance[msg.sender] += _redeemableBalance;
        shortProfits += longs[msg.sender].margin;
        longTokens -= longs[msg.sender].tokens;
        longShares -= longs[msg.sender].shares;

        delete longs[msg.sender];
        emit ClosedLoss(longs[msg.sender]);
        return longs[msg.sender];
    }

    function liquidatePosition(address account) public returns (Position memory) {
        /// @notice  Wrapper function to liquidate position based on Position type
        /// @param   account: Address of account to liquidate

        if (shorts[account].active == true) {
            if (currentPrice() < shorts[msg.sender].liquidation) revert NotLiquidatable();

            longProfits += shorts[account].margin;
            shortTokens -= shorts[account].tokens;
            shortShares -= shorts[account].shares;

            delete shorts[account];
            emit Liquidated(shorts[account]);
            return shorts[account];
        } else if (longs[account].active == true) {
            if (currentPrice() > longs[msg.sender].liquidation) revert NotLiquidatable();

            shortProfits += longs[account].margin;
            longTokens -= longs[account].tokens;
            longShares -= longs[account].shares;

            delete longs[account];
            emit Liquidated(longs[account]);
            return longs[account];
        } else {
            revert NoOpenPosition();
        }
    }

    function addMargin(uint256 amount) external returns (Position memory) {
        /// @notice  Wrapper function for adding margin based on position side
        /// @param   amount: Number of collateral to add to position
        /// @dev     Deleverages position, updating new liquidation price
        /// @return  Position that was updated

        if (shorts[msg.sender].active == true) {
            uint256 _entry = shorts[msg.sender].entry;
            uint256 _newMargin = shorts[msg.sender].margin + amount;
            uint256 _newLeverage = shorts[msg.sender].tokens / _newMargin;
            uint256 _newLiquidation = _entry + (_entry / _newLeverage);
            uint256 _newProfit = _entry - (_entry / _newLeverage);

            balance[msg.sender] -= amount;
            shorts[msg.sender].margin = _newMargin;
            shorts[msg.sender].leverage = _newLeverage;
            shorts[msg.sender].liquidation = _newLiquidation;
            shorts[msg.sender].profit = _newProfit;

            emit MarginAdded(shorts[msg.sender]);
            return shorts[msg.sender];
        } else if (longs[msg.sender].active == true) {
            uint256 _entry = longs[msg.sender].entry;
            uint256 _newMargin = longs[msg.sender].margin + amount;
            uint256 _newLeverage = longs[msg.sender].tokens / _newMargin;
            uint256 _newLiquidation = _entry - (_entry / _newLeverage);
            uint256 _newProfit = _entry + (_entry / _newLeverage);

            balance[msg.sender] -= amount;
            longs[msg.sender].margin = _newMargin;
            longs[msg.sender].leverage = _newLeverage;
            longs[msg.sender].liquidation = _newLiquidation;
            longs[msg.sender].profit = _newProfit;

            emit MarginAdded(longs[msg.sender]);
            return longs[msg.sender];
        } else {
            revert NoOpenPosition();
        }
    }

    function fundingRate(address account) external {
        /// @notice  Wrapper function checks which side pays funding rate
        /// @param   account: Address of account to update
        /// @dev     If both sides are equal or funding rate not owed, updates position funding due time

        if (shorts[account].active == true && shortTokens > longTokens) _shortsPayLongs(account);
        else if (longs[account].active == true && longTokens > shortTokens) _longsPayShorts(account);
        else _updateFunding(account);
    }

    function _shortsPayLongs(address account) internal returns (Position memory) {
        /// @notice Funding rate is paid by shorts to longs
        /// @param  account: Address of account to update
        /// @dev    Releverages position, updating new liquidation and profit thresholds
        /// @return Position that was updated

        if (shorts[account].funding > block.timestamp) revert FundingNotDue();

        uint256 _shortRatio = shortTokens * PRECISION / shortTokens + longTokens;
        uint256 _longRatio = longTokens * PRECISION / longTokens + shortTokens;
        uint256 _intervalFundingRate = _shortRatio - _longRatio * PRECISION / FUNDING_PERIODS;
        uint256 _fundingRateDue = shorts[account].tokens * _intervalFundingRate / shortTokens;

        if (_fundingRateDue >= shorts[account].margin) {
            longProfits += shorts[account].margin;
            shortTokens -= shorts[account].tokens;
            shortShares -= shorts[account].shares;

            delete shorts[account];
            emit Liquidated(shorts[account]);
            return shorts[account];
        } else {
            uint256 _entry = shorts[account].entry;
            uint256 _newMargin = shorts[account].margin - _fundingRateDue;
            uint256 _newLeverage = shorts[account].tokens / _newMargin;
            uint256 _newLiquidation = _entry + (_entry / _newLeverage);
            uint256 _newProfit = _entry - (_entry / _newLeverage);

            longProfits += _fundingRateDue;
            shorts[account].margin = _newMargin;
            shorts[account].leverage = _newLeverage;
            shorts[account].liquidation = _newLiquidation;
            shorts[account].profit = _newProfit;
            shorts[account].funding = block.timestamp + FUNDING_INTERVAL;

            emit FundingPaid(shorts[account]);
            return shorts[account];
        }
    }

    function _longsPayShorts(address account) internal returns (Position memory) {
        /// @notice Funding rate is paid by longs to shorts
        /// @param  account: Address of account to update
        /// @dev    Releverages position, updating new liquidation and profit thresholds
        /// @return Position that was updated

        if (longs[account].funding > block.timestamp) revert FundingNotDue();

        uint256 _longRatio = longTokens * PRECISION / longTokens + shortTokens;
        uint256 _shortRatio = shortTokens * PRECISION / shortTokens + longTokens;
        uint256 _intervalFundingRate = _longRatio - _shortRatio * PRECISION / FUNDING_PERIODS;
        uint256 _fundingRateDue = longs[account].tokens * _intervalFundingRate / longTokens;

        if (_fundingRateDue >= longs[account].margin) {
            shortProfits += longs[account].margin;
            longTokens -= longs[account].tokens;
            longShares -= longs[account].shares;

            delete longs[account];
            emit Liquidated(longs[account]);
            return longs[account];
        } else {
            uint256 _entry = longs[account].entry;
            uint256 _newMargin = longs[msg.sender].margin - _fundingRateDue;
            uint256 _newLeverage = longs[account].tokens / _newMargin;
            uint256 _newLiquidation = _entry - (_entry / _newLeverage);
            uint256 _newProfit = _entry + (_entry / _newLeverage);

            shortProfits += _fundingRateDue;
            longs[account].margin = _newMargin;
            longs[account].leverage = _newLeverage;
            longs[account].liquidation = _newLiquidation;
            longs[account].profit = _newProfit;
            longs[account].funding = block.timestamp + FUNDING_INTERVAL;

            emit FundingPaid(longs[account]);
            return longs[account];
        }
    }

    function _updateFunding(address account) internal returns (Position memory) {
        /// @notice  Triggered when funding rate is balanced euqally
        /// @param   address: Account to update funding rate

        if (shorts[account].active == true) {
            shorts[account].funding = block.timestamp + FUNDING_INTERVAL;
            emit FundingPaid(shorts[account]);
            return shorts[account];
        } else if (longs[account].active == true) {
            longs[account].funding = block.timestamp + FUNDING_INTERVAL;
            emit FundingPaid(longs[account]);
            return longs[account];
        } else {
            revert NoOpenPosition();
        }
    }
}
