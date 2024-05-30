// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Parimutuel.sol";
import {Math} from "../src/libraries/Math.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import "../test/mocks/MockV3Aggregator.sol";
import "../test/mocks/FakeUSD.sol";
import "forge-std/console.sol";

contract ParimutuelTest is Test, Math {
    using stdStorage for StdStorage;

    uint256 public constant FUNDING_INTERVAL = 21600;
    uint256 public constant FUNDING_PERIODS = 1460;
    uint256 public constant MIN_LEVERAGE = 1 * PRECISION;
    uint256 public constant MAX_LEVERAGE = 100 * PRECISION;
    uint256 public constant PRECISION = 10 ** 18;
    uint256 public constant MIN_MARGIN = PRECISION;

    uint256 public depositAmount = 1000 * PRECISION;
    address public fakeUser = address(0x123);

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

    Parimutuel public parimutuel;
    MockV3Aggregator public priceOracle;
    FakeUSD public settlementToken;

    address admin;

    function setUp() public {
        admin = address(0x1); // Set admin persona
        vm.prank(admin); // Use vm.prank to simulate the admin deploying the contract

        priceOracle = new MockV3Aggregator(4000); // Set initial price
        settlementToken = new FakeUSD();
        parimutuel = new Parimutuel(
            address(priceOracle),
            address(settlementToken)
        );

        deal(address(settlementToken), fakeUser, depositAmount);
        vm.prank(fakeUser);
        settlementToken.approve(address(parimutuel), depositAmount);
        vm.prank(fakeUser);
        parimutuel.deposit(depositAmount);
    }

    function testConstructorInitializesCorrectly() public {
        // Use vm.prank to simulate the admin deploying the contract
        vm.prank(admin);
        Parimutuel testParimutuel = new Parimutuel(
            address(priceOracle),
            address(settlementToken)
        );

        assertEq(
            address(testParimutuel.priceOracle()),
            address(priceOracle),
            "Price oracle address should match"
        );
        assertEq(
            address(testParimutuel.settlementToken()),
            address(settlementToken),
            "Settlement token address should match"
        );
        assertEq(testParimutuel.admin(), admin, "Admin address should match");
    }

    function testCurrentPrice() public {
        // Arrange: Set a specific price in the MockV3Aggregator
        int256 expectedPrice = 4000 * int256(PRECISION); // Assuming price in the MockV3Aggregator is scaled by PRECISION
        priceOracle.updateAnswer(expectedPrice);

        // Act: Get the current price from the Parimutuel contract
        uint256 actualPrice = parimutuel.currentPrice();

        // Assert: Verify that the current price matches the expected price
        assertEq(
            actualPrice,
            uint256(expectedPrice),
            "The current price should match the price set in the oracle"
        );
    }

    function testDeposit(uint256 _depositAmount) public {
        // Assume valid deposit amount
        vm.assume(_depositAmount > 0 && _depositAmount <= 1000 * PRECISION);

        deal(address(settlementToken), fakeUser, _depositAmount);
        vm.prank(fakeUser);
        settlementToken.approve(address(parimutuel), _depositAmount);

        // Act and Assert: Simulate the fake user depositing tokens
        vm.prank(fakeUser);
        vm.expectEmit(true, true, true, true);
        emit Deposit(fakeUser, _depositAmount);
        parimutuel.deposit(_depositAmount);

        // Assert: Verify the balance is updated correctly
        assertEq(
            parimutuel.balance(fakeUser),
            depositAmount + _depositAmount,
            "Deposit should update the user's balance correctly"
        );
    }

    function testDepositZeroTokensReverts() public {
        // Act and Assert: Simulate the fake user attempting to deposit zero tokens, expecting it to revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.AmountMustBeGreaterThanZero.selector);
        parimutuel.deposit(0);
    }

    function testDepositTransferFailsReverts(uint256 _depositAmount) public {
        // Assume valid deposit amount
        vm.assume(_depositAmount > 0 && _depositAmount <= 1000 * PRECISION);

        deal(address(settlementToken), fakeUser, _depositAmount);
        vm.prank(fakeUser);
        settlementToken.approve(address(parimutuel), _depositAmount);

        // Mock the settlementToken transferFrom to fail
        vm.mockCall(
            address(settlementToken),
            abi.encodeWithSelector(
                settlementToken.transferFrom.selector,
                fakeUser,
                address(parimutuel),
                _depositAmount
            ),
            abi.encode(false)
        );

        // Act and Assert: Simulate the fake user attempting to deposit tokens, expecting it to revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.TransferFailed.selector);
        parimutuel.deposit(_depositAmount);
    }

    function testWithdraw(uint256 withdrawAmount) public {
        // Assume valid withdraw amount
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);

        // Act and Assert: Simulate the fake user withdrawing tokens
        vm.prank(fakeUser);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(fakeUser, withdrawAmount);
        parimutuel.withdraw(withdrawAmount);

        // Assert: Verify the balance is updated correctly
        assertEq(
            parimutuel.balance(fakeUser),
            depositAmount - withdrawAmount,
            "Withdraw should update the user's balance correctly"
        );
        assertEq(
            settlementToken.balanceOf(fakeUser),
            withdrawAmount,
            "User should receive the withdrawn tokens"
        );
    }

    function testWithdrawInsufficientBalanceReverts(
        uint256 withdrawAmount
    ) public {
        // Assume withdraw amount exceeds deposit amount
        vm.assume(withdrawAmount > depositAmount);

        // Act and Assert: Expect the call to revert with InsufficientBalance
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InsufficientBalance.selector);
        parimutuel.withdraw(withdrawAmount);
    }

    function testWithdrawZeroTokensReverts() public {
        // Act and Assert: Simulate the fake user attempting to withdraw zero tokens, expecting it to revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.AmountMustBeGreaterThanZero.selector);
        parimutuel.withdraw(0);
    }

    function testWithdrawTransferFailsReverts(uint256 withdrawAmount) public {
        // Assume valid withdraw amount
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);

        // Mock the settlementToken transfer to fail
        vm.mockCall(
            address(settlementToken),
            abi.encodeWithSelector(
                settlementToken.transfer.selector,
                fakeUser,
                withdrawAmount
            ),
            abi.encode(false)
        );

        // Act and Assert: Expect the call to revert with TransferFailed
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.TransferFailed.selector);
        parimutuel.withdraw(withdrawAmount);
    }
    function testOpenShortInsufficientMargin(uint256 margin) public {
        // Assume invalid margin below minimum margin
        vm.assume(margin > 0 && margin < MIN_MARGIN);
        vm.assume(depositAmount >= margin);
        uint256 leverage = 2 * PRECISION; // Use a valid leverage

        // Act and Assert: Expect the call to revert with InsufficientMargin
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InsufficientMargin.selector);
        parimutuel.openShort(margin, leverage);
    }

    function testOpenShortInvalidLeverageBelowMinimum(uint256 margin) public {
        // Assume valid margin
        vm.assume(margin >= MIN_MARGIN);
        vm.assume(depositAmount >= margin);

        // Set leverage below minimum
        uint256 leverage = MIN_LEVERAGE - 1; // Invalid leverage just below minimum

        // Act and Assert: Expect the call to revert with InvalidLeverage
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InvalidLeverage.selector);
        parimutuel.openShort(margin, leverage);
    }

    function testOpenShortInvalidLeverageAboveMaximum(uint256 margin) public {
        // Assume valid margin
        vm.assume(margin >= MIN_MARGIN);
        vm.assume(depositAmount >= margin);

        // Set leverage above maximum
        uint256 leverage = MAX_LEVERAGE + 1; // Invalid leverage just above maximum

        // Act and Assert: Expect the call to revert with InvalidLeverage
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InvalidLeverage.selector);
        parimutuel.openShort(margin, leverage);
    }

    function testOpenShort() public {
        // Use fixed values for margin and leverage
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        uint256 startShortTokens = parimutuel.shortTokens();
        uint256 startShortShares = parimutuel.shortShares();

        // Act: Call the openShort function
        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openShort(
            margin,
            leverage
        );

        uint256 expectedTokens = margin * leverage;
        uint256 expectedEntry = parimutuel.currentPrice();
        uint256 expectedLiquidation = expectedEntry +
            (expectedEntry / leverage);
        uint256 expectedProfit = expectedEntry - (expectedEntry / leverage);
        uint256 expectedShares = Math.sqrt(startShortTokens + expectedTokens) -
            startShortShares;
        uint256 expectedFunding = block.timestamp + FUNDING_INTERVAL;

        // Adjust margin calculation to match the contract logic
        uint256 leverageFee = 0;
        uint256 adjustedMargin = margin;
        if (startShortTokens > 0) {
            uint256 totalTokens = startShortTokens + expectedTokens;
            uint256 dilution = (expectedTokens * PRECISION) / totalTokens;
            leverageFee = (dilution * margin) / PRECISION;
            adjustedMargin = margin - leverageFee;
        }

        // Check the position fields
        assertEq(position.active, true, "Position should be active");
        assertEq(position.margin, adjustedMargin, "Margin should match");
        assertEq(position.leverage, leverage, "Leverage should match");
        assertEq(position.tokens, expectedTokens, "Tokens should match");
        assertEq(position.entry, expectedEntry, "Entry price should match");
        assertEq(
            position.liquidation,
            expectedLiquidation,
            "Liquidation price should match"
        );
        assertEq(position.profit, expectedProfit, "Profit price should match");
        assertEq(position.shares, expectedShares, "Shares should match");
        assertEq(
            position.funding,
            expectedFunding,
            "Funding timestamp should match"
        );
    }

    function setUpExistingShortPositions() internal {
        uint256 margin = depositAmount;
        uint256 leverage = 10 * PRECISION; // 10x leverage
        uint256 count = 10;

        for (uint256 i = 0; i < count; i++) {
            // Generate a unique fake user address
            address uniqueFakeUser = address(
                uint160(uint256(keccak256(abi.encodePacked(i))))
            );

            // Deal the required balance to the fake user
            deal(address(settlementToken), uniqueFakeUser, margin);
            vm.prank(uniqueFakeUser);
            settlementToken.approve(address(parimutuel), margin);

            vm.prank(uniqueFakeUser);
            parimutuel.deposit(margin);

            vm.prank(uniqueFakeUser);
            parimutuel.openShort(margin, leverage);
        }
    }

    function testOpenShortWithExistingPositions() public {
        // Set up initial conditions with pre-existing short positions
        setUpExistingShortPositions();

        // Use fixed values for margin and leverage
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        uint256 startShortTokens = parimutuel.shortTokens();
        uint256 startShortShares = parimutuel.shortShares();

        // Act: Call the openShort function
        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openShort(
            margin,
            leverage
        );

        uint256 expectedTokens = margin * leverage;
        uint256 expectedEntry = parimutuel.currentPrice();
        uint256 expectedLiquidation = expectedEntry +
            (expectedEntry / leverage);
        uint256 expectedProfit = expectedEntry - (expectedEntry / leverage);
        uint256 expectedShares = Math.sqrt(startShortTokens + expectedTokens) -
            startShortShares;
        uint256 expectedFunding = block.timestamp + FUNDING_INTERVAL;

        // Adjust margin calculation to match the contract logic
        uint256 leverageFee = 0;
        uint256 adjustedMargin = margin;
        if (startShortTokens > 0) {
            uint256 totalTokens = startShortTokens + expectedTokens;
            uint256 dilution = (expectedTokens * PRECISION) / totalTokens;
            leverageFee = (dilution * margin) / PRECISION;
            adjustedMargin = margin - leverageFee;
        }

        // Check the position fields
        assertEq(position.active, true, "Position should be active");
        assertEq(position.margin, adjustedMargin, "Margin should match");
        assertEq(position.leverage, leverage, "Leverage should match");
        assertEq(position.tokens, expectedTokens, "Tokens should match");
        assertEq(position.entry, expectedEntry, "Entry price should match");
        assertEq(
            position.liquidation,
            expectedLiquidation,
            "Liquidation price should match"
        );
        assertEq(position.profit, expectedProfit, "Profit price should match");
        assertEq(position.shares, expectedShares, "Shares should match");
        assertEq(
            position.funding,
            expectedFunding,
            "Funding timestamp should match"
        );
    }
    function testLiquidateNonActiveShortReverts() public {
        // Set up initial conditions
        uint256 margin = MIN_MARGIN;
        uint256 leverage = 2 * PRECISION;

        // Act: Open and then close a short position
        vm.prank(fakeUser);
        parimutuel.openShort(margin, leverage);

        vm.prank(fakeUser);
        parimutuel.closeShort(); // Close the short position

        // Attempt to liquidate a non-active short position
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NoActiveShort.selector);
        parimutuel.liquidateShort(fakeUser);
    }

    function testLiquidateShortBelowLiquidationPriceReverts() public {
        // Set up initial conditions
        uint256 margin = MIN_MARGIN;
        uint256 leverage = 2 * PRECISION;

        // Act: Open a short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openShort(
            margin,
            leverage
        );

        // Set the price to below the liquidation price
        uint256 belowLiquidationPrice = position.liquidation - 1;
        priceOracle.updateAnswer(int256(belowLiquidationPrice));

        // Attempt to liquidate the short position when the current price is below the liquidation price
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NotLiquidatable.selector);
        parimutuel.liquidateShort(fakeUser);
    }

    function testLiquidateShortAtOrAboveLiquidationPrice() public {
        // Set up initial conditions
        uint256 margin = MIN_MARGIN;
        uint256 leverage = 2 * PRECISION;

        // Act: Open a short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openShort(
            margin,
            leverage
        );

        // Mock the price to be at the liquidation price
        uint256 liquidationPrice = (parimutuel.currentPrice() *
            (100 * PRECISION + leverage)) / (100 * PRECISION);
        priceOracle.updateAnswer(int256(liquidationPrice));

        uint256 expectedTokens = parimutuel.shortTokens() - position0.tokens;
        uint256 expectedShares = parimutuel.shortShares() - position0.shares;
        uint256 expectedLongProfits = parimutuel.longProfits() +
            position0.margin;

        // Liquidate the short position when the current price is at or above the liquidation price
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.liquidateShort(
            fakeUser
        );

        // Assert: Verify that the state is updated correctly
        assertEq(
            parimutuel.shortTokens(),
            expectedTokens,
            "Short tokens should be updated correctly"
        );
        assertEq(
            parimutuel.shortShares(),
            expectedShares,
            "Short shares should be updated correctly"
        );
        assertEq(
            parimutuel.longProfits(),
            expectedLongProfits,
            "Long profits should be updated correctly"
        );
        assertEq(
            position1.active,
            false,
            "Position should no longer be active"
        );
    }
    function testCloseShortLoss() public {
        // Arrange: Set up initial conditions with a short position
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openShort(
            margin,
            leverage
        );

        // Act: Simulate market conditions where the short position is at a loss
        uint256 lossPrice = position0.entry + 1; // Assume the price drops below the entry price
        priceOracle.updateAnswer(int256(lossPrice));

        // Act: Close the short position at a loss
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeShortLoss();

        // Assert: Verify the position is no longer active
        assertEq(
            position1.active,
            false,
            "Position should be closed and inactive"
        );

        // Additional state checks if necessary
        // e.g., checking balances, remaining tokens, etc.
    }

    function testCloseShortLossNoActiveShortReverts() public {
        // Act and Assert: Attempt to close a non-existent short position
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NoActiveShort.selector);
        parimutuel.closeShortLoss();
    }

    function testCloseShortLossNotCloseableAtLossReverts() public {
        // Arrange: Set up initial conditions with a short position
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openShort(
            margin,
            leverage
        );

        // Act: Simulate market conditions where the short position is not at a loss
        uint256 noLossPrice = position.entry - 1; // Assume the price rises above the entry price
        priceOracle.updateAnswer(int256(noLossPrice));

        // Act and Assert: Attempt to close the short position, expecting a revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NotCloseableAtLoss.selector);
        parimutuel.closeShortLoss();
    }
    function testCloseShortProfit() public {
        // Arrange: Set up initial conditions with a short position
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openShort(
            margin,
            leverage
        );

        // Act: Simulate market conditions where the short position is at a profit
        uint256 profitPrice = position0.entry - 1; // Assume the price drops below the entry price
        priceOracle.updateAnswer(int256(profitPrice));

        // Act: Close the short position at a profit
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeShortProfit();

        // Assert: Verify the position is no longer active
        assertEq(
            position1.active,
            false,
            "Position should be closed and inactive"
        );

        // Additional state checks if necessary
        // e.g., checking balances, remaining tokens, etc.
    }

    function testCloseShortProfitNoActiveShortReverts() public {
        // Act and Assert: Attempt to close a non-existent short position
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NoActiveShort.selector);
        parimutuel.closeShortProfit();
    }

    function testCloseShortProfitNotCloseableAtProfitReverts() public {
        // Arrange: Set up initial conditions with a short position
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openShort(
            margin,
            leverage
        );

        // Act: Simulate market conditions where the short position is not at a profit
        uint256 noProfitPrice = position.entry + 1; // Assume the price rises above the entry price
        priceOracle.updateAnswer(int256(noProfitPrice));

        // Act and Assert: Attempt to close the short position, expecting a revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NotCloseableAtProfit.selector);
        parimutuel.closeShortProfit();
    }
    function testOpenLongInsufficientMargin(uint256 margin) public {
        // Assume invalid margin below minimum margin
        vm.assume(margin > 0 && margin < MIN_MARGIN);
        vm.assume(depositAmount >= margin);
        uint256 leverage = 2 * PRECISION; // Use a valid leverage

        // Act and Assert: Expect the call to revert with InsufficientMargin
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InsufficientMargin.selector);
        parimutuel.openLong(margin, leverage);
    }

    function testOpenLongInvalidLeverageBelowMinimum(uint256 margin) public {
        // Assume valid margin
        vm.assume(margin >= MIN_MARGIN);
        vm.assume(depositAmount >= margin);

        // Set leverage below minimum
        uint256 leverage = MIN_LEVERAGE - 1; // Invalid leverage just below minimum

        // Act and Assert: Expect the call to revert with InvalidLeverage
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InvalidLeverage.selector);
        parimutuel.openLong(margin, leverage);
    }

    function testOpenLongInvalidLeverageAboveMaximum(uint256 margin) public {
        // Assume valid margin
        vm.assume(margin >= MIN_MARGIN);
        vm.assume(depositAmount >= margin);

        // Set leverage above maximum
        uint256 leverage = MAX_LEVERAGE + 1; // Invalid leverage just above maximum

        // Act and Assert: Expect the call to revert with InvalidLeverage
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InvalidLeverage.selector);
        parimutuel.openLong(margin, leverage);
    }

    function testOpenLong() public {
        // Use fixed values for margin and leverage
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        uint256 startLongTokens = parimutuel.longTokens();
        uint256 startLongShares = parimutuel.longShares();

        // Act: Call the openLong function
        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openLong(
            margin,
            leverage
        );

        uint256 expectedTokens = margin * leverage;
        uint256 expectedEntry = parimutuel.currentPrice();
        uint256 expectedLiquidation = expectedEntry -
            (expectedEntry / leverage);
        uint256 expectedProfit = expectedEntry + (expectedEntry / leverage);
        uint256 expectedShares = Math.sqrt(startLongTokens + expectedTokens) -
            startLongShares;
        uint256 expectedFunding = block.timestamp + FUNDING_INTERVAL;

        // Adjust margin calculation to match the contract logic
        uint256 leverageFee = 0;
        uint256 adjustedMargin = margin;
        if (startLongTokens > 0) {
            uint256 totalTokens = startLongTokens + expectedTokens;
            uint256 dilution = (expectedTokens * PRECISION) / totalTokens;
            leverageFee = (dilution * margin) / PRECISION;
            adjustedMargin = margin - leverageFee;
        }

        // Check the position fields
        assertEq(position.active, true, "Position should be active");
        assertEq(position.margin, adjustedMargin, "Margin should match");
        assertEq(position.leverage, leverage, "Leverage should match");
        assertEq(position.tokens, expectedTokens, "Tokens should match");
        assertEq(position.entry, expectedEntry, "Entry price should match");
        assertEq(
            position.liquidation,
            expectedLiquidation,
            "Liquidation price should match"
        );
        assertEq(position.profit, expectedProfit, "Profit price should match");
        assertEq(position.shares, expectedShares, "Shares should match");
        assertEq(
            position.funding,
            expectedFunding,
            "Funding timestamp should match"
        );
    }

    function setUpExistingLongPositions() internal {
        uint256 margin = depositAmount;
        uint256 leverage = 10 * PRECISION; // 10x leverage
        uint256 count = 10;

        for (uint256 i = 0; i < count; i++) {
            // Generate a unique fake user address
            address uniqueFakeUser = address(
                uint160(uint256(keccak256(abi.encodePacked(i))))
            );

            // Deal the required balance to the fake user
            deal(address(settlementToken), uniqueFakeUser, margin);
            vm.prank(uniqueFakeUser);
            settlementToken.approve(address(parimutuel), margin);

            vm.prank(uniqueFakeUser);
            parimutuel.deposit(margin);

            vm.prank(uniqueFakeUser);
            parimutuel.openLong(margin, leverage);
        }
    }

    function testOpenLongWithExistingPositions() public {
        // Set up initial conditions with pre-existing long positions
        setUpExistingLongPositions();

        // Use fixed values for margin and leverage
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        uint256 startLongTokens = parimutuel.longTokens();
        uint256 startLongShares = parimutuel.longShares();

        // Act: Call the openLong function
        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openLong(
            margin,
            leverage
        );

        uint256 expectedTokens = margin * leverage;
        uint256 expectedEntry = parimutuel.currentPrice();
        uint256 expectedLiquidation = expectedEntry -
            (expectedEntry / leverage);
        uint256 expectedProfit = expectedEntry + (expectedEntry / leverage);
        uint256 expectedShares = Math.sqrt(startLongTokens + expectedTokens) -
            startLongShares;
        uint256 expectedFunding = block.timestamp + FUNDING_INTERVAL;

        // Adjust margin calculation to match the contract logic
        uint256 leverageFee = 0;
        uint256 adjustedMargin = margin;
        if (startLongTokens > 0) {
            uint256 totalTokens = startLongTokens + expectedTokens;
            uint256 dilution = (expectedTokens * PRECISION) / totalTokens;
            leverageFee = (dilution * margin) / PRECISION;
            adjustedMargin = margin - leverageFee;
        }

        // Check the position fields
        assertEq(position.active, true, "Position should be active");
        assertEq(position.margin, adjustedMargin, "Margin should match");
        assertEq(position.leverage, leverage, "Leverage should match");
        assertEq(position.tokens, expectedTokens, "Tokens should match");
        assertEq(position.entry, expectedEntry, "Entry price should match");
        assertEq(
            position.liquidation,
            expectedLiquidation,
            "Liquidation price should match"
        );
        assertEq(position.profit, expectedProfit, "Profit price should match");
        assertEq(position.shares, expectedShares, "Shares should match");
        assertEq(
            position.funding,
            expectedFunding,
            "Funding timestamp should match"
        );
    }

    function testLiquidateNonActiveLongReverts() public {
        // Set up initial conditions
        uint256 margin = MIN_MARGIN;
        uint256 leverage = 2 * PRECISION;

        // Act: Open and then close a long position
        vm.prank(fakeUser);
        parimutuel.openLong(margin, leverage);

        vm.prank(fakeUser);
        parimutuel.closeLong(); // Close the long position

        // Attempt to liquidate a non-active long position
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NoActiveLong.selector);
        parimutuel.liquidateLong(fakeUser);
    }

    function testLiquidateLongBelowLiquidationPriceReverts() public {
        // Set up initial conditions
        uint256 margin = MIN_MARGIN;
        uint256 leverage = 2 * PRECISION;

        // Act: Open a long position
        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openLong(
            margin,
            leverage
        );

        // Set the price to below the liquidation price
        uint256 belowLiquidationPrice = position.liquidation + 1;
        priceOracle.updateAnswer(int256(belowLiquidationPrice));

        // Attempt to liquidate the long position when the current price is below the liquidation price
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NotLiquidatable.selector);
        parimutuel.liquidateLong(fakeUser);
    }

    function testLiquidateLongAtOrAboveLiquidationPrice() public {
        // Set up initial conditions
        uint256 margin = MIN_MARGIN;
        uint256 leverage = 2 * PRECISION;

        // Act: Open a long position
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openLong(
            margin,
            leverage
        );

        // Mock the price to be at the liquidation price
        uint256 liquidationPrice = (parimutuel.currentPrice() *
            (100 * PRECISION - leverage)) / (100 * PRECISION);
        priceOracle.updateAnswer(int256(liquidationPrice));

        uint256 expectedTokens = parimutuel.longTokens() - position0.tokens;
        uint256 expectedShares = parimutuel.longShares() - position0.shares;
        uint256 expectedShortProfits = parimutuel.shortProfits() +
            position0.margin;

        // Liquidate the long position when the current price is at or above the liquidation price
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.liquidateLong(
            fakeUser
        );

        // Assert: Verify that the state is updated correctly
        assertEq(
            parimutuel.longTokens(),
            expectedTokens,
            "Long tokens should be updated correctly"
        );
        assertEq(
            parimutuel.longShares(),
            expectedShares,
            "Long shares should be updated correctly"
        );
        assertEq(
            parimutuel.shortProfits(),
            expectedShortProfits,
            "Short profits should be updated correctly"
        );
        assertEq(
            position1.active,
            false,
            "Position should no longer be active"
        );
    }

    function testCloseLongLoss() public {
        // Arrange: Set up initial conditions with a long position
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openLong(
            margin,
            leverage
        );

        // Act: Simulate market conditions where the long position is at a loss
        uint256 lossPrice = position0.entry - 1; // Assume the price rises above the entry price
        priceOracle.updateAnswer(int256(lossPrice));

        // Act: Close the long position at a loss
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeLongLoss();

        // Assert: Verify the position is no longer active
        assertEq(
            position1.active,
            false,
            "Position should be closed and inactive"
        );

        // Additional state checks if necessary
        // e.g., checking balances, remaining tokens, etc.
    }

    function testCloseLongLossNoActiveLongReverts() public {
        // Act and Assert: Attempt to close a non-existent long position
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NoActiveLong.selector);
        parimutuel.closeLongLoss();
    }

    function testCloseLongLossNotCloseableAtLossReverts() public {
        // Arrange: Set up initial conditions with a long position
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openLong(
            margin,
            leverage
        );

        // Act: Simulate market conditions where the long position is not at a loss
        uint256 noLossPrice = position.entry + 1; // Assume the price drops below the entry price
        priceOracle.updateAnswer(int256(noLossPrice));

        // Act and Assert: Attempt to close the long position, expecting a revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NotCloseableAtLoss.selector);
        parimutuel.closeLongLoss();
    }

    function testCloseLongProfit() public {
        // Arrange: Set up initial conditions with a long position
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openLong(
            margin,
            leverage
        );

        // Act: Simulate market conditions where the long position is at a profit
        uint256 profitPrice = position0.entry + 1; // Assume the price drops below the entry price
        priceOracle.updateAnswer(int256(profitPrice));

        // Act: Close the long position at a profit
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeLongProfit();

        // Assert: Verify the position is no longer active
        assertEq(
            position1.active,
            false,
            "Position should be closed and inactive"
        );

        // Additional state checks if necessary
        // e.g., checking balances, remaining tokens, etc.
    }

    function testCloseLongProfitNoActiveLongReverts() public {
        // Act and Assert: Attempt to close a non-existent long position
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NoActiveLong.selector);
        parimutuel.closeLongProfit();
    }

    function testCloseLongProfitNotCloseableAtProfitReverts() public {
        // Arrange: Set up initial conditions with a long position
        uint256 margin = depositAmount; // 1000 tokens
        uint256 leverage = 10 * PRECISION; // 10x leverage

        vm.prank(fakeUser);
        Parimutuel.Position memory position = parimutuel.openLong(
            margin,
            leverage
        );

        // Act: Simulate market conditions where the long position is not at a profit
        uint256 noProfitPrice = position.entry - 1; // Assume the price rises above the entry price
        priceOracle.updateAnswer(int256(noProfitPrice));

        // Act and Assert: Attempt to close the long position, expecting a revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.NotCloseableAtProfit.selector);
        parimutuel.closeLongProfit();
    }
    function testCloseShort_Liquidation() public {
        uint256 margin = 1000 * PRECISION; // Example margin
        uint256 leverage = 10 * PRECISION; // Example leverage

        // Open a short position to start with
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openShort(
            margin,
            leverage
        );

        uint256 liquidationPrice = position0.liquidation;

        // Set the price to just above the liquidation price
        priceOracle.updateAnswer(int256(liquidationPrice + 1));

        // Close the short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeShort();

        // Ensure position is inactive
        assertEq(
            position1.active,
            false,
            "Position should be inactive after liquidation"
        );
    }
    function testCloseShort_Loss() public {
        uint256 margin = 1000 * PRECISION; // Example margin
        uint256 leverage = 10 * PRECISION; // Example leverage

        // Open a short position to start with
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openShort(
            margin,
            leverage
        );

        uint256 entryPrice = position0.entry;

        // Set the price just above the entry price but below liquidation
        priceOracle.updateAnswer(int256(entryPrice + 1));

        // Close the short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeShort();

        // Ensure position is inactive
        assertEq(
            position1.active,
            false,
            "Position should be inactive after closing with loss"
        );
    }
    function testCloseShort_Profit() public {
        uint256 margin = 1000 * PRECISION; // Example margin
        uint256 leverage = 10 * PRECISION; // Example leverage

        // Open a short position to start with
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openShort(
            margin,
            leverage
        );

        uint256 entryPrice = position0.entry;

        // Set the price just below the entry price
        priceOracle.updateAnswer(int256(entryPrice - 1));

        // Close the short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeShort();

        // Ensure position is inactive
        assertEq(
            position1.active,
            false,
            "Position should be inactive after closing with profit"
        );
    }
    function testCloseShort_NoActiveShort() public {
        // Attempting to close a position when no active short exists should revert
        vm.expectRevert(NoActiveShort.selector);
        vm.prank(fakeUser);
        parimutuel.closeShort();
    }
    function testCloseLong_Liquidation() public {
        uint256 margin = 1000 * PRECISION; // Example margin
        uint256 leverage = 10 * PRECISION; // Example leverage

        // Open a long position to start with
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openLong(
            margin,
            leverage
        );

        uint256 liquidationPrice = position0.liquidation;

        // Set the price to just below the liquidation price
        priceOracle.updateAnswer(int256(liquidationPrice - 1));

        // Close the long position
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeLong();

        // Ensure position is inactive
        assertEq(
            position1.active,
            false,
            "Position should be inactive after liquidation"
        );
    }
    function testCloseLong_Loss() public {
        uint256 margin = 1000 * PRECISION; // Example margin
        uint256 leverage = 10 * PRECISION; // Example leverage

        // Open a long position to start with
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openLong(
            margin,
            leverage
        );

        uint256 entryPrice = position0.entry;

        // Set the price just below the entry price but above liquidation
        priceOracle.updateAnswer(int256(entryPrice - 1));

        // Close the long position
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeLong();

        // Ensure position is inactive
        assertEq(
            position1.active,
            false,
            "Position should be inactive after closing with loss"
        );
    }
    function testCloseLong_Profit() public {
        uint256 margin = 1000 * PRECISION; // Example margin
        uint256 leverage = 10 * PRECISION; // Example leverage

        // Open a long position to start with
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openLong(
            margin,
            leverage
        );

        uint256 entryPrice = position0.entry;

        // Set the price just above the entry price
        priceOracle.updateAnswer(int256(entryPrice + 1));

        // Close the long position
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.closeLong();

        // Ensure position is inactive
        assertEq(
            position1.active,
            false,
            "Position should be inactive after closing with profit"
        );
    }
    function testCloseLong_NoActiveLong() public {
        // Attempting to close a position when no active long exists should revert
        vm.expectRevert(NoActiveLong.selector);
        vm.prank(fakeUser);
        parimutuel.closeLong();
    }
    function testFundingRateShort_NoActiveShort() public {
        bytes memory expectedRevert = abi.encodeWithSignature(
            "NoActiveShort()"
        );

        vm.expectRevert(expectedRevert);
        parimutuel.fundingRateShort(address(0x124));
    }

    function testFundingRateShort_FundingRateNotDue() public {
        uint256 margin = 1000 * PRECISION;
        uint256 leverage = 10 * PRECISION;

        // Open a short position
        vm.prank(fakeUser);
        parimutuel.openShort(margin, leverage);

        vm.warp(block.timestamp + FUNDING_INTERVAL / 2); // Move forward in time but not enough to be due

        bytes memory expectedRevert = abi.encodeWithSignature(
            "FundingRateNotDue()"
        );

        vm.expectRevert(expectedRevert);
        vm.prank(fakeUser);
        parimutuel.fundingRateShort(fakeUser);
    }

    function testFundingRateShort_ShortTokensLessThanLongTokens() public {
        stdstore.target(address(parimutuel)).sig("shortTokens()").checked_write(
            (9_000_000 * PRECISION) * PRECISION
        );
        stdstore.target(address(parimutuel)).sig("longTokens()").checked_write(
            (10_000_000 * PRECISION) * PRECISION
        );

        uint256 margin = 1000 * PRECISION;
        uint256 leverage = 10 * PRECISION;

        // Open a short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openShort(
            margin,
            leverage
        );

        // Move forward in time to be due for funding
        vm.warp(position0.funding + 1);

        // Check initial funding time
        uint256 initialFundingTime = position0.funding;
        uint256 intitialMargin = position0.margin;

        // Call fundingRateShort
        vm.prank(fakeUser);

        // Get the updated position
        Parimutuel.Position memory position1 = parimutuel.fundingRateShort(
            fakeUser
        );

        // Ensure the funding time is updated correctly
        assertEq(
            position1.funding,
            initialFundingTime + FUNDING_INTERVAL,
            "Funding time should be updated"
        );
        assertEq(
            intitialMargin,
            position1.margin,
            "Margin should stay equal to the initial"
        );
    }

    function testFundingRateShort_ShortTokensMoreThanLongTokens() public {
        stdstore.target(address(parimutuel)).sig("shortTokens()").checked_write(
            (10_000_000 * PRECISION) * PRECISION
        );
        stdstore.target(address(parimutuel)).sig("longTokens()").checked_write(
            (9_000_000 * PRECISION) * PRECISION
        );

        uint256 margin = 1000 * PRECISION;
        uint256 leverage = 10 * PRECISION;

        // Open a short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openShort(
            margin,
            leverage
        );

        // Move forward in time to be due for funding
        vm.warp(position0.funding + 1);

        // Check initial funding time
        uint256 initialFundingTime = position0.funding;
        uint256 intitialMargin = position0.margin;

        // Call fundingRateShort
        vm.prank(fakeUser);

        // Get the updated position
        Parimutuel.Position memory position1 = parimutuel.fundingRateShort(
            fakeUser
        );

        // Ensure the funding time is updated correctly
        assertEq(
            position1.funding,
            initialFundingTime + FUNDING_INTERVAL,
            "Funding time should be updated"
        );
        assert(intitialMargin > position1.margin);
    }

    function testFundingRateLong_NoActiveLong() public {
        bytes memory expectedRevert = abi.encodeWithSignature("NoActiveLong()");

        vm.expectRevert(expectedRevert);
        parimutuel.fundingRateLong(address(0x124));
    }

    function testFundingRateLong_FundingRateNotDue() public {
        uint256 margin = 1000 * PRECISION;
        uint256 leverage = 10 * PRECISION;

        // Open a short position
        vm.prank(fakeUser);
        parimutuel.openLong(margin, leverage);

        vm.warp(block.timestamp + FUNDING_INTERVAL / 2); // Move forward in time but not enough to be due

        bytes memory expectedRevert = abi.encodeWithSignature(
            "FundingRateNotDue()"
        );

        vm.expectRevert(expectedRevert);
        vm.prank(fakeUser);
        parimutuel.fundingRateLong(fakeUser);
    }

    function testFundingRateLong_LongTokensLessThanShortTokens() public {
        stdstore.target(address(parimutuel)).sig("shortTokens()").checked_write(
            (10_000_000 * PRECISION) * PRECISION
        );
        stdstore.target(address(parimutuel)).sig("longTokens()").checked_write(
            (9_000_000 * PRECISION) * PRECISION
        );

        uint256 margin = 1000 * PRECISION;
        uint256 leverage = 10 * PRECISION;

        // Open a short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openLong(
            margin,
            leverage
        );

        // Move forward in time to be due for funding
        vm.warp(position0.funding + 1);

        // Check initial funding time
        uint256 initialFundingTime = position0.funding;
        uint256 intitialMargin = position0.margin;

        // Call fundingRateShort
        vm.prank(fakeUser);

        // Get the updated position
        Parimutuel.Position memory position1 = parimutuel.fundingRateLong(
            fakeUser
        );

        // Ensure the funding time is updated correctly
        assertEq(
            position1.funding,
            initialFundingTime + FUNDING_INTERVAL,
            "Funding time should be updated"
        );
        assertEq(
            intitialMargin,
            position1.margin,
            "Margin should stay equal to the initial"
        );
    }

    function testFundingRateLong_LongTokensMoreThanShortTokens() public {
        stdstore.target(address(parimutuel)).sig("shortTokens()").checked_write(
            (9_000_000 * PRECISION) * PRECISION
        );
        stdstore.target(address(parimutuel)).sig("longTokens()").checked_write(
            (10_000_000 * PRECISION) * PRECISION
        );

        uint256 margin = 1000 * PRECISION;
        uint256 leverage = 10 * PRECISION;

        // Open a short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openLong(
            margin,
            leverage
        );

        // Move forward in time to be due for funding
        vm.warp(position0.funding + 1);

        // Check initial funding time
        uint256 initialFundingTime = position0.funding;
        uint256 intitialMargin = position0.margin;

        // Call fundingRateShort
        vm.prank(fakeUser);

        // Get the updated position
        Parimutuel.Position memory position1 = parimutuel.fundingRateLong(
            fakeUser
        );

        // Ensure the funding time is updated correctly
        assertEq(
            position1.funding,
            initialFundingTime + FUNDING_INTERVAL,
            "Funding time should be updated"
        );
        assert(intitialMargin > position1.margin);
    }

    function testAddMarginShort_Success() public {
        uint256 initialMargin = 1000 * PRECISION;
        uint256 additionalMargin = 500 * PRECISION;
        uint256 leverage = 10 * PRECISION;

        // Open a short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openShort(
            initialMargin,
            leverage
        );

        deal(address(settlementToken), fakeUser, additionalMargin);
        vm.prank(fakeUser);
        settlementToken.approve(address(parimutuel), additionalMargin);
        vm.prank(fakeUser);
        parimutuel.deposit(additionalMargin);

        // Add margin to the short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.addMarginShort(
            fakeUser,
            additionalMargin
        );

        // Check the new margin
        assertEq(
            position1.margin,
            position0.margin + additionalMargin,
            "Margin should be updated correctly"
        );
    }
    function testAddMarginLong_Success() public {
        uint256 initialMargin = 1000 * PRECISION;
        uint256 additionalMargin = 500 * PRECISION;
        uint256 leverage = 10 * PRECISION;

        // Open a short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position0 = parimutuel.openLong(
            initialMargin,
            leverage
        );

        deal(address(settlementToken), fakeUser, additionalMargin);
        vm.prank(fakeUser);
        settlementToken.approve(address(parimutuel), additionalMargin);
        vm.prank(fakeUser);
        parimutuel.deposit(additionalMargin);

        // Add margin to the short position
        vm.prank(fakeUser);
        Parimutuel.Position memory position1 = parimutuel.addMarginLong(
            fakeUser,
            additionalMargin
        );

        // Check the new margin
        assertEq(
            position1.margin,
            position0.margin + additionalMargin,
            "Margin should be updated correctly"
        );
    }
}
