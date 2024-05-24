//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import {Math} from "../contracts/libraries/Math.sol";
import {Test, console2} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {console2} from "forge-std/console2.sol";
import {FakeUSD} from "../contracts/FakeUSD.sol";
import {Parimutuel} from "../contracts/Parimutuel.sol";
import {ScaffoldETHDeploy} from "../script/DeployHelpers.s.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
//import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ParimutuelTest is ScaffoldETHDeploy, Test, Math {
    using stdStorage for StdStorage;

    FakeUSD fakeUSD;
    MockV3Aggregator priceFeed;
    Parimutuel parimutuel;

    error InvalidPrivateKey(string);

    uint8 public constant DECIMALS = 18;
    uint256 public constant PRECISION = 10 ** 18;
    uint256 public constant STARTING_BALANCE = 1_000 * PRECISION;
    uint256 public constant SHORT_PROFITS = 5_000 * PRECISION;
    uint256 public constant LONG_PROFITS = 5_000 * PRECISION;
    int256 public constant ETH_USD_PRICE = 2_000 * int256(PRECISION);

    address USER = makeAddr("user");
    address DEPLOYER = makeAddr("deployer");
    uint256 constant STARTING_ETH = 1 ether;

    address SHORT0 = makeAddr("short0");
    address SHORT1 = makeAddr("short1");
    address SHORT2 = makeAddr("short2");
    address SHORT3 = makeAddr("short3");
    address SHORT4 = makeAddr("short4");
    address SHORT5 = makeAddr("short5");
    address SHORT6 = makeAddr("short6");
    address SHORT7 = makeAddr("short7");
    address SHORT8 = makeAddr("short8");
    address SHORT9 = makeAddr("short9");

    address LONG0 = makeAddr("long0");
    address LONG1 = makeAddr("long1");
    address LONG2 = makeAddr("long2");
    address LONG3 = makeAddr("long3");
    address LONG4 = makeAddr("long4");
    address LONG5 = makeAddr("long5");
    address LONG6 = makeAddr("long6");
    address LONG7 = makeAddr("long7");
    address LONG8 = makeAddr("long8");
    address LONG9 = makeAddr("long9");

    address[] public shorts = [SHORT0, SHORT1, SHORT2, SHORT3, SHORT4, SHORT5, SHORT6, SHORT7, SHORT8, SHORT9];
    address[] public longs = [LONG0, LONG1, LONG2, LONG3, LONG4, LONG5, LONG6, LONG7, LONG8, LONG9];

    function setUp() external {
        vm.startBroadcast(DEPLOYER);

        fakeUSD = new FakeUSD();
        priceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        parimutuel = new Parimutuel(address(priceFeed), address(fakeUSD));

        vm.stopBroadcast();
        exportDeployments();

        stdstore.target(address(parimutuel)).sig("shortProfits()").checked_write(SHORT_PROFITS);
        stdstore.target(address(parimutuel)).sig("longProfits()").checked_write(LONG_PROFITS);

        for (uint256 short = 0; short < shorts.length; short++) {
            vm.deal(shorts[short], STARTING_ETH);
            vm.startPrank(shorts[short]);
            parimutuel.faucet();
            parimutuel.openShort(STARTING_BALANCE, short + 1);
            vm.stopPrank();
        }

        for (uint256 long = 0; long < longs.length; long++) {
            vm.deal(longs[long], STARTING_ETH);
            vm.startPrank(longs[long]);
            parimutuel.faucet();
            parimutuel.openLong(STARTING_BALANCE, long + 1);
            vm.stopPrank();
        }

        vm.deal(USER, STARTING_ETH);
    }

    modifier funded() {
        vm.prank(USER);
        fakeUSD.mint();
        _;
    }

    modifier deposited() {
        vm.startPrank(USER);
        // fakeUSD.mint();
        // fakeUSD.approve(address(parimutuel), STARTING_BALANCE);
        //parimutuel.userDeposit(FAKE_USD_AMOUNT);
        parimutuel.faucet();
        vm.stopPrank();
        _;
    }

    modifier shortOpened() {
        vm.prank(USER);
        parimutuel.openShort(1000e18, 10);
        _;
    }

    modifier longOpened() {
        vm.prank(USER);
        parimutuel.openLong(1000e18, 10);
        _;
    }

    // function testFakeUSDMint() public {
    //     vm.prank(USER);
    //     fakeUSD.mint();
    //     assertEq(fakeUSD.balanceOf(USER), STARTING_BALANCE);
    //     console.logString(vm.toString(address(USER)));
    // }

    // function testUserDeposit() public {
    //     vm.startPrank(USER);
    //     fakeUSD.mint();
    //     fakeUSD.approve(address(parimutuel), FAKE_USD_AMOUNT);
    //     //parimutuel.userDeposit(FAKE_USD_AMOUNT);
    //     vm.stopPrank();
    //     assertEq(parimutuel.balance(USER), FAKE_USD_AMOUNT);
    // }

    function testFaucet() public {
        vm.startPrank(USER);
        parimutuel.faucet();
        vm.stopPrank();
        assertEq(parimutuel.balance(USER), STARTING_BALANCE);
    }

    // function testUserWithdrawal() public {
    //     uint256 _balance = parimutuel.balance(USER);
    //     console.log(_balance);
    //     vm.prank(USER);
    //     //parimutuel.userWithdrawal(_balance);
    //     assertEq(fakeUSD.balanceOf(USER), _balance);
    // }

    // function testUserWithdrawalNotEnoughFunds() public {
    //     uint256 _withdrawalAmount = parimutuel.balance(USER) + 1;
    //     vm.prank(USER);
    //     vm.expectRevert();
    //     //parimutuel.userWithdrawal(_withdrawalAmount);
    // }

    function testOpenShortRevertsNotEnoughFunds(uint256 margin, uint256 leverage) public deposited {
        vm.assume(margin > STARTING_BALANCE);
        vm.assume(leverage > 1 || leverage < 100);
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.openShort(margin, leverage);
    }

    function testOpenShortRevertsLeverageNotAllowed(uint256 margin, uint256 leverage) public {
        vm.assume(margin < STARTING_BALANCE);
        vm.assume(leverage < 1 || leverage > 100);
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.openShort(margin, leverage);
    }

    function testOpenShortRevertsShortAlreadyOpen(uint256 margin, uint256 leverage) public deposited shortOpened {
        vm.assume(margin < STARTING_BALANCE);
        vm.assume(leverage > 1 || leverage < 100);
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.openShort(margin, leverage);
    }

    function testOpenShortRevertsLongAlreadyOpen(uint256 margin, uint256 leverage) public deposited longOpened {
        vm.assume(margin < STARTING_BALANCE);
        vm.assume(leverage > 1 || leverage < 100);
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.openShort(margin, leverage);
    }

    function testOpenShortOnly(uint256 margin, uint256 leverage) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage <= 100);

        uint256 _margin = margin * PRECISION;
        uint256 _leverage = leverage;
        uint256 _expectedTokens = _margin * _leverage;
        uint256 _expectedEntry = parimutuel.currentPrice();
        uint256 _expectedLiquidation = _expectedEntry + (_expectedEntry / _leverage);
        uint256 _expectedProfit = _expectedEntry - (_expectedEntry / _leverage);
        uint256 _expectedShares = Math.sqrt(parimutuel.shortTokens() + _expectedTokens) - parimutuel.shortShares();
        uint256 _expectedFunding = block.timestamp + parimutuel.FUNDING_INTERVAL();

        uint256 _initialShortTokens = parimutuel.shortTokens();
        uint256 _initialShortShares = parimutuel.shortShares();
        uint256 _initialUserBalance = parimutuel.balance(USER);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openShort(_margin, _leverage);

        assertEq(position.active, true, "Active");
        assertEq(position.margin, _margin, "Margin");
        assertEq(position.leverage, _leverage, "Leverage");
        assertEq(position.tokens, _expectedTokens, "Tokens");
        assertEq(position.entry, _expectedEntry, "Entry");
        assertEq(position.liquidation, _expectedLiquidation, "Liquidation");
        assertEq(position.profit, _expectedProfit, "Profit");
        assertEq(position.shares, _expectedShares, "Shares");
        assertEq(position.funding, _expectedFunding, "Funding");
        assertEq(parimutuel.shortTokens(), position.tokens + _initialShortTokens, "Total Tokens");
        assertEq(parimutuel.shortShares(), position.shares + _initialShortShares, "Total Shares");
        assertEq(parimutuel.balance(USER), _initialUserBalance - _margin, "User Balance");
    }

    function testCloseShortRevertsNoOpenPosition() public {
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.closeShort();
    }

    function testCloseShortLiquidate(uint256 margin, uint256 leverage) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage < 100);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openShort(margin * PRECISION, leverage);

        uint256 _startinglongProfits = parimutuel.longProfits();
        uint256 _startingShortTokens = parimutuel.shortTokens();
        uint256 _startingShortShares = parimutuel.shortShares();

        uint256 _liquidatedMargin = position.margin;
        uint256 _liquidatedShortTokens = position.tokens;
        uint256 _liquidatedShortShares = position.shares;

        int256 _updatedPrice = int256(position.liquidation) + 1;
        priceFeed.updateAnswer(_updatedPrice);

        vm.prank(USER);
        parimutuel.closeShort();
        (bool _active,,,,,,,,) = parimutuel.shorts(USER);

        assertEq(_active, false, "Position Closed");
        assertEq(parimutuel.longProfits(), _startinglongProfits + _liquidatedMargin, "Ending Long Profits");
        assertEq(parimutuel.shortTokens(), _startingShortTokens - _liquidatedShortTokens, "Ending Short Tokens");
        assertEq(parimutuel.shortShares(), _startingShortShares - _liquidatedShortShares, "Ending Short Shares");
    }

    function testCloseShortAboveProfit(uint256 margin, uint256 leverage, int256 price) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage < 100);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openShort(margin * PRECISION, leverage);

        uint256 _startingBalance = parimutuel.balance(USER);
        uint256 _startingShortTokens = parimutuel.shortTokens();
        uint256 _startingShortProfits = parimutuel.shortProfits();
        uint256 _startingShortShares = parimutuel.shortShares();

        vm.assume(price <= int256(position.profit));
        priceFeed.updateAnswer(price);

        uint256 _profitRatio = position.shares * PRECISION / _startingShortShares;
        uint256 _profits = _startingShortProfits * _profitRatio / PRECISION;
        uint256 _profitsAfterFees = _profits * 995 / 1000;
        uint256 _feesPaid = _profits - _profitsAfterFees;

        vm.prank(USER);
        parimutuel.closeShort();
        (bool _active,,,,,,,,) = parimutuel.shorts(USER);

        assertEq(_active, false, "Position Closed");
        assertEq(parimutuel.shortProfits(), _startingShortProfits - _profits, "Total Short Profits");
        assertEq(parimutuel.shortTokens(), _startingShortTokens - position.tokens, "Total Short Tokens");
        assertEq(parimutuel.shortShares(), _startingShortShares - position.shares, "Total Short Shares");
        assertEq(parimutuel.balance(USER), _startingBalance + _profitsAfterFees + position.margin, "User Balance");
        assertEq(parimutuel.balance(DEPLOYER), _feesPaid, "Admin Balance");
    }

    function testCloseShortBelowProfit(uint256 margin, uint256 leverage, uint256 priceDecrease) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage < 100);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openShort(margin * PRECISION, leverage);

        uint256 _startingBalance = parimutuel.balance(USER);
        uint256 _startingShortProfits = parimutuel.shortProfits();
        uint256 _startingShortTokens = parimutuel.shortTokens();
        uint256 _startingShortShares = parimutuel.shortShares();
        uint256 _entryMinusProfit = (position.entry - position.profit) / PRECISION;

        priceDecrease = bound(priceDecrease, 1, _entryMinusProfit);
        priceFeed.updateAnswer(int256(position.entry - (priceDecrease * PRECISION)));

        uint256 _entry = position.entry;
        uint256 _effectiveShares = position.shares * (_entry - parimutuel.currentPrice()) / (_entry - position.profit);
        uint256 _profitRatio = _effectiveShares * PRECISION / parimutuel.shortShares();
        uint256 _profits = parimutuel.shortProfits() * _profitRatio / PRECISION;
        uint256 _profitsAfterFees = _profits * 995 / 1000;
        uint256 _feesPaid = _profits - _profitsAfterFees;

        vm.prank(USER);
        parimutuel.closeShort();
        (bool _active,,,,,,,,) = parimutuel.shorts(USER);

        assertEq(_active, false, "Position Closed");
        assertEq(parimutuel.shortProfits(), _startingShortProfits - _profits, "Total Short Profits");
        assertEq(parimutuel.shortTokens(), _startingShortTokens - position.tokens, "Total Short Tokens");
        assertEq(parimutuel.shortShares(), _startingShortShares - position.shares, "Total ShortShares");
        assertEq(parimutuel.balance(USER), _startingBalance + position.margin + _profitsAfterFees, "User Balance");
        assertEq(parimutuel.balance(DEPLOYER), _feesPaid, "Admin Balance");
    }

    function testCloseShortLoss(uint256 margin, uint256 leverage, uint256 priceIncrease) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage < 100);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openShort(margin * PRECISION, leverage);

        uint256 _startingBalance = parimutuel.balance(USER);
        uint256 _startingLongProfits = parimutuel.longProfits();
        uint256 _startingShortTokens = parimutuel.shortTokens();
        uint256 _startingShortShares = parimutuel.shortShares();

        uint256 _liquidationMinusEntry = (position.liquidation - position.entry) / PRECISION;
        priceIncrease = bound(priceIncrease, 1, _liquidationMinusEntry);
        priceFeed.updateAnswer(int256(position.entry + (priceIncrease * PRECISION)));

        uint256 _currentPrice = parimutuel.currentPrice();
        uint256 _liquidation = position.liquidation;
        uint256 _numerator = _liquidation - _currentPrice;
        uint256 _denominator = _liquidation - position.entry;
        uint256 _redeemableBalance = position.margin * _numerator / _denominator;
        uint256 _longProfits = position.margin - _redeemableBalance;

        vm.prank(USER);
        parimutuel.closeShort();
        (bool _active,,,,,,,,) = parimutuel.shorts(USER);

        assertEq(_active, false, "Position Closed");
        assertEq(parimutuel.balance(USER), _startingBalance + _redeemableBalance, "User Balance");
        assertEq(parimutuel.longProfits(), _startingLongProfits + _longProfits, "Total Long Profits");
        assertEq(parimutuel.shortTokens(), _startingShortTokens - position.tokens, "Total Short Tokens");
        assertEq(parimutuel.shortShares(), _startingShortShares - position.shares, "Total Short Shares");
    }

    function testOpenLongRevertsNotEnoughFunds(uint256 margin, uint256 leverage) public deposited {
        vm.assume(margin > STARTING_BALANCE);
        vm.assume(leverage > 1 || leverage < 100);
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.openLong(margin, leverage);
    }

    function testOpenLongRevertsLeverageNotAllowed(uint256 margin, uint256 leverage) public {
        vm.assume(margin < STARTING_BALANCE);
        vm.assume(leverage < 1 || leverage > 100);
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.openLong(margin, leverage);
    }

    function testOpenLongRevertsShortAlreadyOpen(uint256 margin, uint256 leverage) public deposited shortOpened {
        vm.assume(margin < STARTING_BALANCE);
        vm.assume(leverage > 1 || leverage < 100);
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.openLong(margin, leverage);
    }

    function testOpenLongRevertsLongAlreadyOpen(uint256 margin, uint256 leverage) public deposited longOpened {
        vm.assume(margin < STARTING_BALANCE);
        vm.assume(leverage > 1 || leverage < 100);
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.openLong(margin, leverage);
    }

    function testOpenLongOnly(uint256 margin, uint256 leverage) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage <= 100);

        uint256 _margin = margin * PRECISION;
        uint256 _leverage = leverage;
        uint256 _expectedTokens = _margin * _leverage;
        uint256 _expectedEntry = parimutuel.currentPrice();
        uint256 _expectedLiquidation = _expectedEntry - (_expectedEntry / _leverage);
        uint256 _expectedProfit = _expectedEntry + (_expectedEntry / _leverage);
        uint256 _expectedShares = Math.sqrt(parimutuel.longTokens() + _expectedTokens) - parimutuel.longShares();
        uint256 _expectedFunding = block.timestamp + parimutuel.FUNDING_INTERVAL();

        uint256 _initialLongTokens = parimutuel.longTokens();
        uint256 _initialLongShares = parimutuel.longShares();
        uint256 _initialUserBalance = parimutuel.balance(USER);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openLong(_margin, _leverage);

        assertEq(position.active, true, "Active");
        assertEq(position.margin, _margin, "Margin");
        assertEq(position.leverage, _leverage, "Leverage");
        assertEq(position.tokens, _expectedTokens, "Tokens");
        assertEq(position.entry, _expectedEntry, "Entry");
        assertEq(position.liquidation, _expectedLiquidation, "Liquidation");
        assertEq(position.profit, _expectedProfit, "Profit");
        assertEq(position.shares, _expectedShares, "Shares");
        assertEq(position.funding, _expectedFunding, "Funding");
        assertEq(parimutuel.longTokens(), position.tokens + _initialLongTokens, "Final Long Tokens");
        assertEq(parimutuel.longShares(), position.shares + _initialLongShares, "Final Long Shares");
        assertEq(parimutuel.balance(USER), _initialUserBalance - _margin, "User Balance");
    }

    function testCloseLongRevertsNoOpenPosition() public {
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.closeLong();
    }

    function testCloseLongLiquidate(uint256 margin, uint256 leverage) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage < 100);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openLong(margin * PRECISION, leverage);

        uint256 _startingShortProfits = parimutuel.shortProfits();
        uint256 _startingLongTokens = parimutuel.longTokens();
        uint256 _startingLongShares = parimutuel.longShares();

        uint256 _liquidatedMargin = position.margin;
        uint256 _liquidatedLongTokens = position.tokens;
        uint256 _liquidatedLongShares = position.shares;

        int256 _updatedPrice = int256(position.liquidation) - 1;
        priceFeed.updateAnswer(_updatedPrice);

        vm.prank(USER);
        parimutuel.closeLong();
        (bool _active,,,,,,,,) = parimutuel.longs(USER);

        assertEq(_active, false, "Position Closed");
        assertEq(parimutuel.shortProfits(), _startingShortProfits + _liquidatedMargin, "Ending Short Profits");
        assertEq(parimutuel.longTokens(), _startingLongTokens - _liquidatedLongTokens, "Ending Long Tokens");
        assertEq(parimutuel.longShares(), _startingLongShares - _liquidatedLongShares, "Ending Short Shares");
    }

    function testCloseLongAboveProfit(uint256 margin, uint256 leverage) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage < 100);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openLong(margin * PRECISION, leverage);

        uint256 _startingBalance = parimutuel.balance(USER);
        uint256 _startingLongTokens = parimutuel.longTokens();
        uint256 _startingLongProfits = parimutuel.longProfits();
        uint256 _startingLongShares = parimutuel.longShares();

        priceFeed.updateAnswer(int256(position.profit) + 1);

        uint256 _profitRatio = position.shares * PRECISION / _startingLongShares;
        uint256 _profits = _startingLongProfits * _profitRatio / PRECISION;
        uint256 _profitsAfterFees = _profits * 995 / 1000;
        uint256 _feesPaid = _profits - _profitsAfterFees;

        vm.prank(USER);
        parimutuel.closeLong();
        (bool _active,,,,,,,,) = parimutuel.longs(USER);

        assertEq(_active, false, "Position Closed");
        assertEq(parimutuel.longProfits(), _startingLongProfits - _profits, "Total Long Profits");
        assertEq(parimutuel.longTokens(), _startingLongTokens - position.tokens, "Total Long Tokens");
        assertEq(parimutuel.longShares(), _startingLongShares - position.shares, "Total Long Shares");
        assertEq(parimutuel.balance(USER), _startingBalance + _profitsAfterFees + position.margin, "User Balance");
        assertEq(parimutuel.balance(DEPLOYER), _feesPaid, "Admin Balance");
    }

    function testCloseLongBelowProfit(uint256 margin, uint256 leverage, uint256 priceIncrease) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage < 100);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openLong(margin * PRECISION, leverage);

        uint256 _startingBalance = parimutuel.balance(USER);
        uint256 _startingLongProfits = parimutuel.longProfits();
        uint256 _startingLongTokens = parimutuel.longTokens();
        uint256 _startingLongShares = parimutuel.longShares();
        uint256 _entryMinusProfit = (position.profit - position.entry) / PRECISION;

        priceIncrease = bound(priceIncrease, 1, _entryMinusProfit);
        priceFeed.updateAnswer(int256(position.entry + (priceIncrease * PRECISION)));

        uint256 _entry = position.entry;
        uint256 _effectiveShares = position.shares * (parimutuel.currentPrice() - _entry) / (position.profit - _entry);
        uint256 _profitRatio = _effectiveShares * PRECISION / parimutuel.longShares();
        uint256 _profits = parimutuel.longProfits() * _profitRatio / PRECISION;
        uint256 _profitsAfterFees = _profits * 995 / 1000;
        uint256 _feesPaid = _profits - _profitsAfterFees;

        vm.prank(USER);
        parimutuel.closeLong();
        (bool _active,,,,,,,,) = parimutuel.longs(USER);

        assertEq(_active, false, "Position Closed");
        assertEq(parimutuel.longProfits(), _startingLongProfits - _profits, "Total Long Profits");
        assertEq(parimutuel.longTokens(), _startingLongTokens - position.tokens, "Total Long Tokens");
        assertEq(parimutuel.longShares(), _startingLongShares - position.shares, "Total Long Shares");
        assertEq(parimutuel.balance(USER), _startingBalance + position.margin + _profitsAfterFees, "User Balance");
        assertEq(parimutuel.balance(DEPLOYER), _feesPaid, "Admin Balance");
    }

    function testCloseLongLoss(uint256 margin, uint256 leverage, uint256 priceDecrease) public deposited {
        vm.assume(margin <= 1000 && margin > 1);
        vm.assume(leverage > 1 && leverage < 100);

        vm.prank(USER);
        Parimutuel.Position memory position = parimutuel.openLong(margin * PRECISION, leverage);

        uint256 _startingBalance = parimutuel.balance(USER);
        uint256 _startingShortProfits = parimutuel.shortProfits();
        uint256 _startingLongTokens = parimutuel.longTokens();
        uint256 _startingLongShares = parimutuel.longShares();

        uint256 _entryMinusLiquidation = (position.entry - position.liquidation) / PRECISION;
        priceDecrease = bound(priceDecrease, 1, _entryMinusLiquidation);
        priceFeed.updateAnswer(int256(position.entry - (priceDecrease * PRECISION)));

        uint256 _currentPrice = parimutuel.currentPrice();
        uint256 _liquidation = position.liquidation;
        uint256 _numerator = _currentPrice - _liquidation;
        uint256 _denominator = position.entry - _liquidation;
        uint256 _redeemableBalance = position.margin * _numerator / _denominator;
        uint256 _shortProfits = position.margin - _redeemableBalance;

        vm.prank(USER);
        parimutuel.closeLong();
        (bool _active,,,,,,,,) = parimutuel.longs(USER);

        assertEq(_active, false, "Position Closed");
        assertEq(parimutuel.balance(USER), _startingBalance + _redeemableBalance, "User Balance");
        assertEq(parimutuel.shortProfits(), _startingShortProfits + _shortProfits, "Total Short Profits");
        assertEq(parimutuel.longTokens(), _startingLongTokens - position.tokens, "Total Long Tokens");
        assertEq(parimutuel.longShares(), _startingLongShares - position.shares, "Total Long Shares");
    }

    function testLiquidatePositionRevertsNoOpenPosition() public {
        vm.prank(USER);
        vm.expectRevert();
        parimutuel.liquidatePosition(USER);
    }

    // function testLiquidateShortRevertsNotLiquidatable() public {
    //     // (,,,,, uint256 _liquidation,,,) = parimutuel.shorts(SHORT0);
    //     // console.log("Liquidation", _liquidation);
    //     // console.log("Current Price", parimutuel.currentPrice());

    //     vm.prank(USER);
    //     vm.expectRevert();
    //     parimutuel.liquidatePosition(SHORT0);
    // }

    // function testLiquidateLongRevertsNotLiquidatable() public {
    //     // (,,,,, uint256 _liquidation,,,) = parimutuel.longs(LONG0);
    //     // console.log("Liquidation", _liquidation);
    //     // console.log("Current Price", parimutuel.currentPrice());

    //     vm.prank(USER);
    //     vm.expectRevert();
    //     parimutuel.liquidatePosition(LONG0);
    // }

    // function testLiquidateShort() public {
    //     (, uint256 _margin,, uint256 _tokens,, uint256 _liquidation,, uint256 _shares,) = parimutuel.shorts(SHORT9);

    //     console.log("Liquidation", _liquidation);

    //     uint256 _startingLongProfits = parimutuel.longProfits();
    //     uint256 _startingShortTokens = parimutuel.shortTokens();
    //     uint256 _startingShortShares = parimutuel.shortShares();

    //     int256 _updatedPrice = int256(_liquidation) + 1 * 10 ** 18;
    //     priceFeed.updateAnswer(_updatedPrice);

    //     console.log("Current Price", parimutuel.currentPrice());

    //     vm.prank(USER);
    //     Parimutuel.Position memory position = parimutuel.liquidatePosition(SHORT9);

    //     assertEq(parimutuel.longProfits(), _startingLongProfits + _margin, "Total Long Profits");
    //     assertEq(parimutuel.shortTokens(), _startingShortTokens - _tokens, "Total Short Tokens");
    //     assertEq(parimutuel.shortShares(), _startingShortShares - _shares, "Total Short Shares");
    //     assertEq(position.active, false, "Position closed");
    // }
}
