// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/CascadingDonation.sol";

contract CascadingNativeDonationTest is Test {
    CascadingNativeDonation internal _t;
    address payable constant _DONATION_ADDR = payable(address(1001));
    address constant _EOA_ADDR = address(333);

    function setUp() public {
        _t = new CascadingNativeDonation(_DONATION_ADDR, 3);
        vm.deal(_EOA_ADDR, 100);
        vm.startPrank(_EOA_ADDR);
    }

    function test_AddingCommitment_Basic() public {
        assertEq(_EOA_ADDR.balance, 100);
        _t.addCommitment{value: 10 + 3}(5, 10);
        assertEq(_EOA_ADDR.balance, 87);
        assertEq(address(_t).balance, 13);
    }

    function test_AddingCommitment_Insufficient() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CascadingNativeDonation.IncorrectNativeCurrencySent.selector,
                3, 10, 9)
        );
        _t.addCommitment{value: 9}(5, 10);
    }

    function test_AddingCommitment_Overpay() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CascadingNativeDonation.IncorrectNativeCurrencySent.selector,
                3, 10, 14)
        );
        _t.addCommitment{value: 14}(5, 10);
    }

    function test_WithdrawCommitment_Basic() public {
        _t.addCommitment{value: 10 + 3}(5, 10);
        _t.withdrawCommitment(0);
        assertEq(_EOA_ADDR.balance, 100);
        assertEq(address(_t).balance, 0);
    }

    function test_Trigger_Basic() public {
        _t.addCommitment{value: 10 + 3}(5, 10);
        uint128[] memory t = new uint128[](1);
        t[0] = 5;
        _t.trigger(t);
        assertEq(_EOA_ADDR.balance, 90);
        assertEq(address(_t).balance, 0);
        assertEq(_DONATION_ADDR.balance, 10);
    }

    function test_Trigger_AfterExternalDonation() public {
        _t.addCommitment{value: 1 + 3}(5, 1);
        vm.deal(_DONATION_ADDR, 5);
        uint128[] memory t = new uint128[](1);
        t[0] = 5;
        _t.trigger(t);
    }
}

contract TestCoin is ERC20 {
    constructor() ERC20("", "") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract CascadingERC20DonationTest is Test {
    CascadingERC20Donation internal _t;
    TestCoin internal _c;
    address payable constant _DONATION_ADDR = payable(address(1001));
    address constant _EOA_ADDR = address(333);

    function setUp() public {
        _c = new TestCoin();
        _t = new CascadingERC20Donation(_DONATION_ADDR, address(_c), 3);
        vm.deal(_EOA_ADDR, 100);
        _c.mint(_EOA_ADDR, 100);
        vm.startPrank(_EOA_ADDR);
    }

    function test_AddingCommitment_Basic() public {
        assertEq(_EOA_ADDR.balance, 100);
        assertEq(_c.balanceOf(_EOA_ADDR), 100);
        _c.approve(address(_t), 100);
        _t.addCommitment{value: 3}(5, 10);
        assertEq(_EOA_ADDR.balance, 97);
        assertEq(_c.balanceOf(_EOA_ADDR), 90);
        assertEq(address(_t).balance, 3);
        assertEq(_c.balanceOf(address(_t)), 10);
    }

    function test_AddingCommitment_InsufficientNativeCurrency() public {
        _c.approve(address(_t), 100);
        vm.expectRevert(
            abi.encodeWithSelector(
                CascadingERC20Donation.IncorrectNativeCurrencySent.selector,
                3, 2)
        );
        _t.addCommitment{value: 2}(5, 10);
    }

    function test_AddingCommitment_InsufficientERC20Currency() public {
        _c.approve(address(_t), 9);
        vm.expectRevert("ERC20: insufficient allowance");
        _t.addCommitment{value: 3}(5, 10);
    }

    function test_WithdrawCommitment_Basic() public {
        _c.approve(address(_t), 100);
        _t.addCommitment{value: 3}(5, 10);
        _t.withdrawCommitment(0);
        assertEq(_EOA_ADDR.balance, 100);
        assertEq(_c.balanceOf(_EOA_ADDR), 100);
        assertEq(address(_t).balance, 0);
        assertEq(_c.balanceOf(address(_t)), 0);
    }

    function test_Trigger_Basic() public {
        _c.approve(address(_t), 100);
        _t.addCommitment{value: 3}(5, 10);
        uint128[] memory t = new uint128[](1);
        t[0] = 5;
        _t.trigger(t);
        assertEq(_EOA_ADDR.balance, 100);
        assertEq(_c.balanceOf(_EOA_ADDR), 90);
        assertEq(address(_t).balance, 0);
        assertEq(_c.balanceOf(address(_t)), 0);
        assertEq(_DONATION_ADDR.balance, 0);
        assertEq(_c.balanceOf(_DONATION_ADDR), 10);
    }

    function test_Trigger_AfterExternalDonation() public {
        _c.approve(address(_t), 100);
        _t.addCommitment{value: 3}(5, 1);
        _c.mint(_DONATION_ADDR, 5);
        uint128[] memory t = new uint128[](1);
        t[0] = 5;
        _t.trigger(t);
    }
}