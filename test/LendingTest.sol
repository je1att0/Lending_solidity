// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPriceOracle, UpsideAcademyLending} from "../src/UpsideAcademyLending.sol";

contract CUSDC is ERC20 {
    constructor() ERC20("Circle Stable Coin", "USDC") {
        _mint(msg.sender, type(uint256).max);
    }
}

contract UpsideOracle {
    address public operator;
    mapping(address => uint256) prices;

    constructor() {
        operator = msg.sender;
    }

    function getPrice(address token) external view returns (uint256) {
        require(prices[token] != 0, "the price cannot be zero");
        return prices[token];
    }

    function setPrice(address token, uint256 price) external {
        require(msg.sender == operator, "only operator can set the price");
        prices[token] = price;
    }
}

contract Testx is Test {
    UpsideOracle upsideOracle;
    UpsideAcademyLending lending;
    ERC20 usdc;

    address user1;
    address user2;
    address user3;
    address user4;

    function setUp() external {
        user1 = address(0x1337);
        user2 = address(0x1337 + 1);
        user3 = address(0x1337 + 2);
        user4 = address(0x1337 + 3);
        upsideOracle = new UpsideOracle();

        vm.deal(address(this), 10000000 ether);
        usdc = new CUSDC();

        // TDOO 아래 setUp이 정상작동 할 수 있도록 여러분의 Lending Contract를 수정하세요.
        lending = new UpsideAcademyLending(IPriceOracle(address(upsideOracle)), address(usdc));
        usdc.approve(address(lending), type(uint256).max);

        lending.initializeLendingProtocol{value: 1}(address(usdc)); // set reserve ^__^

        upsideOracle.setPrice(address(0x0), 1339 ether);
        upsideOracle.setPrice(address(usdc), 1 ether);
    }

    function testDepositEtherWithoutTxValueFails() external {
        (bool success,) = address(lending).call{value: 0 ether}(
            abi.encodeWithSelector(UpsideAcademyLending.deposit.selector, address(0x0), 1 ether)
        );
        assertFalse(success);
    }

    function testDepositEtherWithInsufficientValueFails() external {
        (bool success,) = address(lending).call{value: 2 ether}(
            abi.encodeWithSelector(UpsideAcademyLending.deposit.selector, address(0x0), 3 ether)
        );
        assertFalse(success);
    }

    function testDepositEtherWithEqualValueSucceeds() external {
        (bool success,) = address(lending).call{value: 2 ether}(
            abi.encodeWithSelector(UpsideAcademyLending.deposit.selector, address(0x0), 2 ether)
        );
        assertTrue(success);
        assertTrue(address(lending).balance == 2 ether + 1);
    }

    function testDepositUSDCWithInsufficientValueFails() external {
        usdc.approve(address(lending), 1);
        (bool success,) = address(lending).call(
            abi.encodeWithSelector(UpsideAcademyLending.deposit.selector, address(usdc), 3000 ether)
        );
        assertFalse(success);
    }

    function testDepositUSDCWithEqualValueSucceeds() external {
        emit log_named_uint("usdc balance", usdc.balanceOf(address(lending)));
        (bool success,) = address(lending).call(
            abi.encodeWithSelector(UpsideAcademyLending.deposit.selector, address(usdc), 2000 ether)
        );
        emit log_named_uint("usdc balance after", usdc.balanceOf(address(lending)));
        assertTrue(success);
        assertTrue(usdc.balanceOf(address(lending)) == 2000 ether + 1);
    }

    function supplyUSDCDepositUser1() private {
        usdc.transfer(user1, 100000000 ether);
        vm.startPrank(user1);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 100000000 ether);
        vm.stopPrank();
    }

    function supplyEtherDepositUser2() private {
        vm.deal(user2, 100000000 ether);
        vm.prank(user2);
        lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);
    }

    function supplySmallEtherDepositUser2() private {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        lending.deposit{value: 1 ether}(address(0x00), 1 ether);
        vm.stopPrank();
    }

    function testBorrowWithInsufficientCollateralFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 1339 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);
            assertTrue(usdc.balanceOf(user2) == 0 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithInsufficientSupplyFails() external {
        supplySmallEtherDepositUser2();
        upsideOracle.setPrice(address(0x0), 99999999999 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);
            assertTrue(usdc.balanceOf(user2) == 0 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithSufficientCollateralSucceeds() external {
        supplyUSDCDepositUser1();
        supplyEtherDepositUser2();

        vm.startPrank(user2);
        {
            lending.borrow(address(usdc), 1000 ether);
            assertTrue(usdc.balanceOf(user2) == 1000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithSufficientSupplySucceeds() external {
        supplyUSDCDepositUser1();
        supplyEtherDepositUser2();

        vm.startPrank(user2);
        {
            lending.borrow(address(usdc), 1000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowMultipleWithInsufficientCollateralFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 3000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            // (uint256 depositedETH, uint256 borrowedUSDC, uint256 lastBlock, uint256 limitLeft) = lending.accounts(user2);
            // emit log_named_uint("limitLeft", limitLeft);
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            // ( depositedETH,  borrowedUSDC, lastBlock, limitLeft) = lending.accounts(user2);
            // emit log_named_uint("limitLeft", limitLeft);

            assertFalse(success);

            assertTrue(usdc.balanceOf(user2) == 1000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowMultipleWithSufficientCollateralSucceeds() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithSufficientCollateralAfterRepaymentSucceeds() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.repay.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testBorrowWithInSufficientCollateralAfterRepaymentFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);

            vm.roll(block.number + 1);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.repay.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 999 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawInsufficientBalanceFails() external {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);

            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 100000001 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testWithdrawUnlockedBalanceSucceeds() external {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);

            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 100000001 ether - 1 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawMultipleUnlockedBalanceSucceeds() external {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);

            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawLockedCollateralFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 1 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testWithdrawLockedCollateralAfterBorrowSucceeds() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether); // 4000 usdc

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            // 2000 * 100 < 75 * (4000 - 1333)
            // 2000 / (1-1333/4000)
            // LT = 75%
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 1 ether * 1333 / 4000)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawLockedCollateralAfterInterestAccuredFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether); // 4000 usdc

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            // 2000 / (4000 - 1333) * 100 = 74.xxxx
            // LT = 75%
            vm.roll(block.number + 1000);
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 1 ether * 1333 / 4000)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testWithdrawYieldSucceeds() external {
        usdc.transfer(user3, 30000000 ether);
        vm.startPrank(user3);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 30000000 ether);
        vm.stopPrank();

        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        bool success;

        vm.startPrank(user2);
        {
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 1 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();

        vm.roll(block.number + (86400 * 1000 / 12));
        vm.prank(user3);
        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30000792);

        vm.roll(block.number + (86400 * 500 / 12));
        vm.prank(user3);
        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30001605);

        vm.prank(user3);
        (success,) = address(lending).call(
            abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(usdc), 30001605 ether)
        );
        assertTrue(success);
        assertTrue(usdc.balanceOf(user3) == 30001605 ether);

        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 0);
    }

    function testExchangeRateChangeAfterUserBorrows() external {
        usdc.transfer(user3, 30000000 ether);
        vm.startPrank(user3);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 30000000 ether);
        vm.stopPrank();

        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.withdraw.selector, address(0x0), 1 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();

        vm.roll(block.number + (86400 * 1000 / 12)); //1000일 후 user3의 예금 = 30000792
        vm.prank(user3);
        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30000792);

        // other lender deposits USDC to our protocol.
        usdc.transfer(user4, 10000000 ether); //1000만 이더
        vm.startPrank(user4);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 10000000 ether);
        vm.stopPrank();

        vm.roll(block.number + (86400 * 500 / 12));  //500일 후
        vm.prank(user3);
        uint256 a = lending.getAccruedSupplyAmount(address(usdc)); //1500일 후 user3의 이자  = 1547 = 792 + 755

        vm.prank(user4);
        uint256 b = lending.getAccruedSupplyAmount(address(usdc)); //500일 후 user4의 이자 = 251

        vm.prank(user1);
        uint256 c = lending.getAccruedSupplyAmount(address(usdc)); //1500일 후 user1의 이자 = 5158 = 2640 + 2518

        assertEq((a + b + c) / 1e18 - 30000000 - 10000000 - 100000000, 6956);
        assertEq(a / 1e18 - 30000000, 1547);
        assertEq(b / 1e18 - 10000000, 251);
    }

    function testWithdrawFullUndilutedAfterDepositByOtherAccountSucceeds() external {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);
        }
        vm.stopPrank();

        vm.deal(user3, 100000000 ether);
        vm.startPrank(user3);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);
        }
        vm.stopPrank();

        vm.startPrank(user2);
        {
            lending.withdraw(address(0x00), 100000000 ether);
            assertEq(address(user2).balance, 100000000 ether);
        }
        vm.stopPrank();
    }

    function testLiquidationHealthyLoanFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        usdc.transfer(user3, 3000 ether);
        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.liquidate.selector, user2, address(usdc), 800 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationUnhealthyLoanSucceeds() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        upsideOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66% // 2640 -> ltv: 1320.
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testLiquidationExceedingDebtFails() external {
        // ** README **
        // can liquidate the whole position when the borrowed amount is less than 100,
        // otherwise only 25% can be liquidated at once.
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        upsideOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.liquidate.selector, user2, address(usdc), 501 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationHealthyLoanAfterPriorLiquidationFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        upsideOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.liquidate.selector, user2, address(usdc), 100 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationAfterBorrowerCollateralDepositFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationAfterDebtPriceDropFails() external {
        // just imagine if USDC falls down
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        upsideOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        upsideOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop Ether price to 66% // 4000 -> 2640 / ltv: 1320
        upsideOracle.setPrice(address(usdc), 1e17); // drop USDC price to 0.1, 90% down // 1 -> 0.1ether
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(UpsideAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    receive() external payable {
        // for ether receive
    }
}