// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Parimutuel.sol";
import {Math} from "../src/libraries/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import "../test/mocks/MockV3Aggregator.sol";
import "../test/mocks/FakeUSD.sol";

contract ParimutuelTest is Test, Math {
    uint256 public constant FUNDING_INTERVAL = 21600;
    uint256 public constant FUNDING_PERIODS = 1460;
    uint256 public constant MIN_LEVERAGE = 1;
    uint256 public constant MAX_LEVERAGE = 100;
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

    Parimutuel public parimutuel;
    MockV3Aggregator public priceOracle;
    FakeUSD public settlementToken;

    address admin;

    function setUp() public {
        admin = address(0x1); // Set admin persona
        vm.prank(admin); // Use vm.prank to simulate the admin deploying the contract

        priceOracle = new MockV3Aggregator(4000);
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
        // Assume invalid margin
        vm.assume(margin > 0);
        vm.assume(margin < MIN_MARGIN);
        uint256 leverage = 2; // Use a valid leverage

        // Act and Assert: Expect the call to revert with InsufficientMargin
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InsufficientMargin.selector);
        parimutuel.openShort(margin, leverage);
    }
    function testOpenShortInvalidLeverageBelowMinimum(uint256 margin) public {
        // Assume valid margin
        vm.assume(margin >= MIN_MARGIN);
        uint256 leverage = MIN_LEVERAGE - 1; // Invalid leverage below minimum

        // Act and Assert: Expect the call to revert with InvalidLeverage
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InvalidLeverage.selector);
        parimutuel.openShort(margin, leverage);
    }
    function testOpenShortInvalidLeverageAboveMaximum(uint256 margin) public {
        // Assume valid margin
        vm.assume(margin >= MIN_MARGIN);
        uint256 leverage = MAX_LEVERAGE + 1; // Invalid leverage above maximum

        // Act and Assert: Expect the call to revert with InvalidLeverage
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InvalidLeverage.selector);
        parimutuel.openShort(margin, leverage);
    }
    function testOpenShort(uint256 margin, uint256 leverage) public {
        // Assume valid margin and leverage range
        vm.assume(margin >= MIN_MARGIN);
        vm.assume(leverage >= MIN_LEVERAGE && leverage <= MAX_LEVERAGE);

        // Ensure the margin does not exceed the deposit amount
        vm.assume(depositAmount >= margin);

        // Act: Call the openShort function
        vm.prank(fakeUser);
        parimutuel.openShort(margin, leverage);

        // Assert: Verify the short position is stored correctly
        (
            bool active,
            uint256 actualMargin,
            uint256 actualLeverage,
            uint256 actualTokens,
            uint256 actualEntry,
            uint256 actualLiquidation,
            uint256 actualProfit,
            uint256 actualShares,
            uint256 actualFunding
        ) = parimutuel.shorts(fakeUser);

        // Calculate expected values directly in the assertions
        assertEq(active, true, "Position should be active");
        assertEq(
            actualMargin,
            margin -
                ((margin * leverage * PRECISION) / parimutuel.shortTokens()) /
                PRECISION,
            "Margin should match"
        );
        assertEq(actualLeverage, leverage, "Leverage should match");
        assertEq(actualTokens, margin * leverage, "Tokens should match");
        assertEq(
            actualEntry,
            parimutuel.currentPrice(),
            "Entry price should match"
        );
        assertEq(
            actualLiquidation,
            (parimutuel.currentPrice() * (100 + leverage)) / 100,
            "Liquidation price should match"
        );
        assertEq(
            actualProfit,
            (parimutuel.currentPrice() * (100 - leverage)) / 100,
            "Profit price should match"
        );
        assertEq(
            actualShares,
            Math.sqrt(parimutuel.shortTokens() + (margin * leverage)) -
                parimutuel.shortShares(),
            "Shares should match"
        );
        assertEq(
            actualFunding,
            block.timestamp + FUNDING_INTERVAL,
            "Funding timestamp should match"
        );
    }
}
