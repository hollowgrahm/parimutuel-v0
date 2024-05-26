// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Parimutuel.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import "../test/mocks/MockV3Aggregator.sol";
import "../test/mocks/FakeUSD.sol";

contract ParimutuelTest is Test {
    uint256 public constant FUNDING_INTERVAL = 21600;
    uint256 public constant FUNDING_PERIODS = 1460;
    uint256 public constant MIN_LEVERAGE = 1;
    uint256 public constant MAX_LEVERAGE = 100;
    uint256 public constant PRECISION = 10 ** 18;
    uint256 public constant MIN_MARGIN = PRECISION;

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
    }

    function setupFakeUser(uint256 amount) internal returns (address fakeUser) {
        fakeUser = address(0x123);
        deal(address(settlementToken), fakeUser, amount);
        vm.prank(fakeUser);
        settlementToken.approve(address(parimutuel), amount);
        vm.prank(fakeUser);
        parimutuel.deposit(amount);
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

    function testDeposit(uint256 depositAmount) public {
        // Arrange: Ensure deposit amount is within a valid range
        vm.assume(depositAmount > 0 && depositAmount <= 1000 * PRECISION);

        // Create a fake user and give them tokens
        address fakeUser = address(0x123);
        deal(address(settlementToken), fakeUser, depositAmount);
        vm.prank(fakeUser);
        settlementToken.approve(address(parimutuel), depositAmount);

        // Act and Assert: Simulate the fake user depositing tokens
        vm.prank(fakeUser);
        vm.expectEmit(true, true, true, true);
        emit Deposit(fakeUser, depositAmount);
        parimutuel.deposit(depositAmount);

        // Assert: Verify the balance is updated correctly
        assertEq(
            parimutuel.balance(fakeUser),
            depositAmount,
            "Deposit should update the user's balance correctly"
        );
    }

    function testDepositZeroTokensReverts() public {
        // Arrange: Create a fake user
        address fakeUser = address(0x123);

        // Act and Assert: Simulate the fake user attempting to deposit zero tokens, expecting it to revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.AmountMustBeGreaterThanZero.selector);
        parimutuel.deposit(0);
    }

    function testDepositTransferFailsReverts(uint256 depositAmount) public {
        // Arrange: Create a fake user and mock a failed transfer
        vm.assume(depositAmount > 0 && depositAmount <= 1000 * PRECISION);
        address fakeUser = setupFakeUser(depositAmount);

        // Mock the settlementToken transferFrom to fail
        vm.mockCall(
            address(settlementToken),
            abi.encodeWithSelector(
                settlementToken.transferFrom.selector,
                fakeUser,
                address(parimutuel),
                depositAmount
            ),
            abi.encode(false)
        );

        // Act and Assert: Simulate the fake user attempting to deposit tokens, expecting it to revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.TransferFailed.selector);
        parimutuel.deposit(depositAmount);
    }

    function testWithdraw(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        // Arrange: Create a fake user and give them tokens
        vm.assume(
            depositAmount >= withdrawAmount &&
                withdrawAmount > 0 &&
                depositAmount <= 1000 * PRECISION
        );
        address fakeUser = setupFakeUser(depositAmount);

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
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        // Arrange: Create a fake user and give them fewer tokens than what will be attempted to withdraw
        vm.assume(
            depositAmount < withdrawAmount &&
                depositAmount > 0 &&
                withdrawAmount <= 1000 * PRECISION
        );
        address fakeUser = setupFakeUser(depositAmount);

        // Act and Assert: Simulate the fake user attempting to withdraw more than the balance, expecting it to revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.InsufficientBalance.selector);
        parimutuel.withdraw(withdrawAmount);
    }

    function testWithdrawZeroTokensReverts(uint256 depositAmount) public {
        // Arrange: Create a fake user and give them tokens
        vm.assume(depositAmount > 0 && depositAmount <= 1000 * PRECISION);
        address fakeUser = setupFakeUser(depositAmount);

        // Act and Assert: Simulate the fake user attempting to withdraw zero tokens, expecting it to revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.AmountMustBeGreaterThanZero.selector);
        parimutuel.withdraw(0);
    }

    function testWithdrawTransferFailsReverts(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        // Arrange: Create a fake user and give them tokens
        vm.assume(
            depositAmount >= withdrawAmount &&
                withdrawAmount > 0 &&
                depositAmount <= 1000 * PRECISION
        );
        address fakeUser = setupFakeUser(depositAmount);

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

        // Act and Assert: Simulate the fake user attempting to withdraw tokens, expecting it to revert
        vm.prank(fakeUser);
        vm.expectRevert(Parimutuel.TransferFailed.selector);
        parimutuel.withdraw(withdrawAmount);
    }
}
