// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Parimutuel.sol";
import "./mocks/MockV3Aggregator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

contract ParimutuelTest is Test {
    //     Parimutuel parimutuel;
    //     IERC20 mockToken;
    //     AggregatorV3Interface mockPriceOracle;
    //     address admin = address(0x123);
    //     function setUp() public {
    //         // Deploy mock contracts
    //         mockToken = IERC20(address(new MockToken()));
    //         mockPriceOracle = AggregatorV3Interface(address(new MockPriceOracle()));
    //         // Deploy the Parimutuel contract
    //         parimutuel = new Parimutuel(
    //             address(mockPriceOracle),
    //             address(mockToken)
    //         );
    //         // Fund the test contract with some tokens
    //         deal(address(mockToken), address(this), 1000 ether);
    //     }
    //     // function testDeposit() public {
    //     //     uint256 initialBalance = parimutuel.balance(address(this));
    //     //     parimutuel.deposit(1 ether);
    //     //     uint256 newBalance = parimutuel.balance(address(this));
    //     //     assertEq(newBalance, initialBalance + 1 ether);
    //     // }
    //     function testWithdraw() public {
    //         parimutuel.deposit(1 ether);
    //         uint256 initialBalance = parimutuel.balance(address(this));
    //         parimutuel.withdraw(1 ether);
    //         uint256 newBalance = parimutuel.balance(address(this));
    //         assertEq(newBalance, initialBalance - 1 ether);
    //     }
    //     function testOpenShortPosition() public {
    //         uint256 margin = 1 ether;
    //         uint256 leverage = 2;
    //         parimutuel.deposit(margin);
    //         parimutuel.openShortPosition(margin, leverage);
    //         Parimutuel.Position memory shortPosition = parimutuel.shorts(
    //             address(this)
    //         );
    //         assertTrue(shortPosition.active);
    //         assertEq(shortPosition.margin, margin);
    //         assertEq(shortPosition.leverage, leverage);
    //     }
    //     function testCloseShortPosition() public {
    //         uint256 margin = 1 ether;
    //         uint256 leverage = 2;
    //         parimutuel.deposit(margin);
    //         parimutuel.openShortPosition(margin, leverage);
    //         parimutuel.closeShort();
    //         Parimutuel.Position memory shortPosition = parimutuel.shorts(
    //             address(this)
    //         );
    //         assertFalse(shortPosition.active);
    //     }
    //     function testOpenShortPositionWithInsufficientMargin() public {
    //         uint256 margin = 0.5 ether;
    //         uint256 leverage = 2;
    //         vm.expectRevert("InsufficientMargin");
    //         parimutuel.openShortPosition(margin, leverage);
    //     }
    //     function testWithdrawWithInsufficientBalance() public {
    //         vm.expectRevert("InsufficientBalance");
    //         parimutuel.withdraw(1 ether);
    //     }
    // }
    // // Mock ERC20 token for testing
    // contract MockToken is IERC20 {
    //     mapping(address => uint256) private _balances;
    //     mapping(address => mapping(address => uint256)) private _allowances;
    //     uint256 private _totalSupply;
    //     function name() external pure returns (string memory) {
    //         return "MockToken";
    //     }
    //     function symbol() external pure returns (string memory) {
    //         return "MKT";
    //     }
    //     function decimals() external pure returns (uint8) {
    //         return 18;
    //     }
    //     function totalSupply() external view returns (uint256) {
    //         return _totalSupply;
    //     }
    //     function balanceOf(address account) external view returns (uint256) {
    //         return _balances[account];
    //     }
    //     function transfer(
    //         address recipient,
    //         uint256 amount
    //     ) external returns (bool) {
    //         _balances[msg.sender] -= amount;
    //         _balances[recipient] += amount;
    //         emit Transfer(msg.sender, recipient, amount);
    //         return true;
    //     }
    //     function allowance(
    //         address owner,
    //         address spender
    //     ) external view returns (uint256) {
    //         return _allowances[owner][spender];
    //     }
    //     function approve(address spender, uint256 amount) external returns (bool) {
    //         _allowances[msg.sender][spender] = amount;
    //         emit Approval(msg.sender, spender, amount);
    //         return true;
    //     }
    //     function transferFrom(
    //         address sender,
    //         address recipient,
    //         uint256 amount
    //     ) external returns (bool) {
    //         _balances[sender] -= amount;
    //         _balances[recipient] += amount;
    //         _allowances[sender][msg.sender] -= amount;
    //         emit Transfer(sender, recipient, amount);
    //         return true;
    //     }
    //     function mint(address account, uint256 amount) external {
    //         _totalSupply += amount;
    //         _balances[account] += amount;
    //         emit Transfer(address(0), account, amount);
    //     }
    // }
    // // Mock Price Oracle for testing
    // contract MockPriceOracle is AggregatorV3Interface {
    //     function decimals() external view override returns (uint8) {
    //         return 18;
    //     }
    //     function description() external view override returns (string memory) {
    //         return "Mock Price Oracle";
    //     }
    //     function version() external view override returns (uint256) {
    //         return 1;
    //     }
    //     function getRoundData(
    //         uint80 _roundId
    //     )
    //         external
    //         view
    //         override
    //         returns (
    //             uint80 roundId,
    //             int256 answer,
    //             uint256 startedAt,
    //             uint256 updatedAt,
    //             uint80 answeredInRound
    //         )
    //     {
    //         return (
    //             _roundId,
    //             2000 * 10 ** 18,
    //             block.timestamp,
    //             block.timestamp,
    //             _roundId
    //         );
    //     }
    //     function latestRoundData()
    //         external
    //         view
    //         override
    //         returns (
    //             uint80 roundId,
    //             int256 answer,
    //             uint256 startedAt,
    //             uint256 updatedAt,
    //             uint80 answeredInRound
    //         )
    //     {
    //         return (0, 2000 * 10 ** 18, block.timestamp, block.timestamp, 0);
    //     }
}
