// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "../src/CascadingERC721Purchase.sol";

contract TestERC721 is ERC721Enumerable {
    constructor(string memory name_, string memory symbol_)
        ERC721(name_, symbol_) {}

    function mint(uint256 num) public payable {
        for (uint256 i = 0; i < num; i++) {
            _safeMint(msg.sender, totalSupply());
        }
    }
}

contract CascadingERC721EnumerablePurchaseTest is Test {
    CascadingERC721EnumerablePurchase internal _t;
    TestERC721 internal _e;
    address constant _EOA_ADDR = address(333);

    function setUp() public {
        _e = new TestERC721("Test", "TERC");
        _t = new CascadingERC721EnumerablePurchase(address(_e), 10, 5, 1, 2, "mint");
        vm.deal(_EOA_ADDR, 100);
        vm.startPrank(_EOA_ADDR);
    }

    function test_AddingCommitment_Basic() public {
        assertEq(_EOA_ADDR.balance, 100);
        _t.addCommitment{value: 3 * 5 + 1 + 2 * 3}(5, 3);
        assertEq(_EOA_ADDR.balance, 78);
        assertEq(address(_t).balance, 22);
    }

    function test_AddingCommitment_Insufficient() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CascadingERC721EnumerablePurchase.IncorrectNativeCurrencySent.selector,
                7, 15, 9)
        );
        _t.addCommitment{value: 9}(5, 3);
    }

    function test_AddingCommitment_Overpay() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CascadingERC721EnumerablePurchase.IncorrectNativeCurrencySent.selector,
                7, 15, 21)
        );
        _t.addCommitment{value: 21}(5, 3);
    }

    function test_WithdrawCommitment_Basic() public {
        _t.addCommitment{value: 22}(5, 3);
        _t.withdrawCommitment(0);
        assertEq(_EOA_ADDR.balance, 100);
        assertEq(address(_t).balance, 0);
    }

    function test_Trigger_Basic() public {
        _t.addCommitment{value: 22}(3, 3);
        uint128[] memory t = new uint128[](1);
        t[0] = 3;
        _t.trigger(t);
        assertEq(_EOA_ADDR.balance, 78 + 1 + 2 * 3);
        assertEq(_e.balanceOf(_EOA_ADDR), 3);
        assertEq(_e.balanceOf(address(_t)), 0);
        assertEq(address(_e).balance, 5 * 3);
    }

    function test_Trigger_ExceedsLimit() public {
        _t.addCommitment{value: 36}(3, 5);
        _t.addCommitment{value: 43}(3, 6);
        uint128[] memory t = new uint128[](1);
        t[0] = 3;
        _t.trigger(t);
        assert(_t.stopped());
        assertEq(_e.balanceOf(_EOA_ADDR), 10);
        assertEq(address(_e).balance, 5 * 10);
        assertEq(address(_t).balance, 2 + 5);

        CommitmentForUser[] memory c = _t.commitments();
        _t.withdrawCommitment(c[0].id);
        assertEq(address(_t).balance, 0);
    }

    function test_Trigger_AfterExternalBuy() public {
        _t.addCommitment{value: 22}(5, 3);
        changePrank(address(334));
        _e.mint(5);
        uint128[] memory t = new uint128[](1);
        t[0] = 3;
        _t.trigger(t);
    }
}
