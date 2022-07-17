// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "../src/CascadingCommitment.sol";

interface ICascadingCommitmentTestExtensions is ICascadingCommitment {
    function setShouldFailCommitment(bool v) external;
    function setNcPerSize(uint128 v) external;
    function triggerLevelWeight(uint128 l) external view returns (uint128);
    function numCommitmentsProcessed() external view returns (uint256);
}

contract TestCascadingCommitment is CascadingCommitment, ICascadingCommitmentTestExtensions {
    bool internal shouldFailCommitment;
    uint256 public numCommitmentsProcessed;
    uint128 public _currentSizeTotal;
    uint128 public ncPerSize;

    function setShouldFailCommitment(bool v) external {
        shouldFailCommitment = v;
    }

    function setNcPerSize(uint128 v) external {
        ncPerSize = v;
    }

    function nativeCurrencyReservedForCommitmentGas(uint128 size)
        public
        view
        virtual
        override(CascadingCommitment, ICascadingCommitment)
        returns (uint128)
    {
        return size * ncPerSize;
    }

    function triggerLevelWeight(uint128 l)
        external
        view
        returns (uint128)
    {
        return triggerLevels[l].totalSize;
    }

    function currentSizeTotal()
        public
        view
        override(CascadingCommitment, ICascadingCommitment)
        returns (uint128)
    {
        return _currentSizeTotal;
    }

    function _checkCommitment(uint128)
        internal
        override
        view
    {
        if (shouldFailCommitment) {
            revert();
        }
    }

    function _refundCommitment(uint128 size)
        internal
        override
    {
        payable(msg.sender).transfer(nativeCurrencyReservedForCommitmentGas(size));
    }

    function _processCommitment(CommitmentInLevel memory c)
        internal
        override
    {
        numCommitmentsProcessed += 1;
        _currentSizeTotal += c.size;
    }
}

contract TestCascadingCommitmentWithSizeLimit is CascadingCommitmentWithSizeLimit, ICascadingCommitmentTestExtensions {
    bool internal shouldFailCommitment;
    uint256 public numCommitmentsProcessed;
    uint128 public ncPerSize;
    uint128 internal _currentSizeTotal;

    constructor(uint128 max) CascadingCommitmentWithSizeLimit(max) {}

    function setShouldFailCommitment(bool v) external {
        shouldFailCommitment = v;
    }

    function setNcPerSize(uint128 v) external {
        ncPerSize = v;
    }

    function nativeCurrencyReservedForCommitmentGas(uint128 size)
        public
        view
        virtual
        override(CascadingCommitment, ICascadingCommitment)
        returns (uint128)
    {
        return size * ncPerSize;
    }

    function currentSizeTotal()
        public
        view
        override(CascadingCommitment, ICascadingCommitment)
        returns (uint128)
    {
        return _currentSizeTotal;
    }

    function triggerLevelWeight(uint128 l)
        external
        view
        returns (uint128)
    {
        return triggerLevels[l].totalSize;
    }

    function _checkCommitment(uint128)
        internal
        override
        view
    {
        if (shouldFailCommitment) {
            revert();
        }
    }

    function _refundCommitment(uint128 size, bool stoppedOn)
        internal
        override
    {
        if (!stoppedOn) {
            payable(msg.sender).transfer(nativeCurrencyReservedForCommitmentGas(size));
        } else {
            payable(msg.sender).transfer(_nativeCurrencyForStopItem);
        }
    }

    function _processCommitment(CommitmentInLevel memory c, uint128)
        internal
        override
        returns (uint128)
    {
        numCommitmentsProcessed += 1;
        if (c.size + _currentSizeTotal <= maxSizeTotal) {
            _currentSizeTotal += c.size;
            return c.size;
        }
        uint128 sp = maxSizeTotal - _currentSizeTotal;
        _currentSizeTotal = maxSizeTotal;
        return sp;
    }
}

contract CascadingCommitmentTest is Test {
    event TriggerLevelSizeChange(uint128 level, uint128 newSize);
    event Triggered(uint128 level);

    ICascadingCommitmentTestExtensions internal _t;
    address constant _EOA_ADDR = address(333);

    function setUp() public virtual {
        _t = new TestCascadingCommitment();
        vm.startPrank(_EOA_ADDR);
    }

    function _triggerSingleLevel(uint128 level) internal {
        uint128[] memory t = new uint128[](1);
        t[0] = level;
        _t.trigger(t);
    }

    function test_AddingCommitment_Basic() public {
        assertEq(_t.currentSizeTotal(), 0);
        assertEq(_t.triggerLevelWeight(5), 0);
        assertEq(_t.commitments().length, 0);

        vm.expectEmit(false, false, false, true);
        emit TriggerLevelSizeChange(5, 2);
        _t.addCommitment(5, 2);

        assertEq(_t.currentSizeTotal(), 0);
        assertEq(_t.triggerLevelWeight(5), 2);
        CommitmentForUser[] memory c = _t.commitments();
        assertEq(c.length, 1);
        assertEq(c[0].triggersAt, 5);
        assertEq(c[0].size, 2);

        vm.stopPrank();
        vm.prank(address(1001));
        assertEq(_t.commitments().length, 0);
    }

    function test_AddingCommitment_Multiple() public {
        _t.addCommitment(5, 2);
        changePrank(address(1001));
        _t.addCommitment(6, 1);
        vm.expectEmit(false, false, false, true);
        emit TriggerLevelSizeChange(5, 6);
        _t.addCommitment(5, 4);
        assertEq(_t.triggerLevelWeight(5), 6);
        CommitmentForUser[] memory c = _t.commitments();
        assertEq(c.length, 2);
        assertEq(c[0].triggersAt, 6);
        assertEq(c[0].size, 1);
        assertEq(c[1].triggersAt, 5);
        assertEq(c[1].size, 4);
    }

    function test_AddingCommitment_NotZeroSize() public {
        vm.expectRevert(CascadingCommitment.BadSize.selector);
        _t.addCommitment(5, 0);
    }

    function test_AddingCommitment_NotZeroTrigger() public {
        vm.expectRevert(CascadingCommitment.AlreadyTriggered.selector);
        _t.addCommitment(0, 2);
    }

    function test_AddingCommitment_NotBelowTriggered() public {
        _t.addCommitment(1, 2);
        changePrank(address(334));
        _triggerSingleLevel(1);
        vm.expectRevert(CascadingCommitment.AlreadyTriggered.selector);
        _t.addCommitment(2, 5);
    }

    function test_WithdrawingCommitment_Basic() public {
        _t.addCommitment(5,2);
        CommitmentForUser[] memory c = _t.commitments();
        _t.withdrawCommitment(c[0].id);
        assertEq(_t.commitments().length, 0);
        assertEq(_t.triggerLevelWeight(5), 0);
    }

    function test_WithdrawingCommitment_Nonexistant() public {
        vm.expectRevert(stdError.indexOOBError);
        _t.withdrawCommitment(1);
    }

    function test_WithdrawingCommitment_Twice() public {
        _t.addCommitment(5,2);
        CommitmentForUser[] memory c = _t.commitments();
        _t.withdrawCommitment(c[0].id);
        vm.expectRevert(CascadingCommitment.BadId.selector);
        _t.withdrawCommitment(c[0].id);
    }

    function test_Trigger_Basic() public {
        _t.addCommitment(5,2);
        _t.addCommitment(5,4);
        vm.expectEmit(false, false, false, true);
        emit Triggered(5);
        _triggerSingleLevel(5);
        assertEq(_t.currentSizeTotal(), 6);
        assertEq(_t.triggerLevelWeight(5), 0);
        assertEq(_t.numCommitmentsProcessed(), 2);
    }

    function test_Trigger_MultipleCommitments() public {
        _t.addCommitment(5, 2);
        _t.addCommitment(4, 3);
        uint128[] memory t = new uint128[](2);
        t[0] = 4;
        t[1] = 5;
        _t.trigger(t);
        assertEq(_t.currentSizeTotal(), 5);
        assertEq(_t.numCommitmentsProcessed(), 2);
    }

    function test_Trigger_MultipleRounds() public {
        _t.addCommitment(5,2);
        _t.addCommitment(5,4);
        _triggerSingleLevel(5);
        assertEq(_t.numCommitmentsProcessed(), 2);
        assertEq(_t.currentSizeTotal(), 6);
        _t.addCommitment(7, 1);
        _triggerSingleLevel(7);
        assertEq(_t.numCommitmentsProcessed(), 3);
        assertEq(_t.currentSizeTotal(), 7);
    }

    function test_Trigger_NativeCurrencyRefund() public {
        _t.setNcPerSize(1);
        vm.deal(address(_t), 10);
        _t.addCommitment(5, 2);
        _t.addCommitment(5, 4);
        _triggerSingleLevel(5);
        assertEq(_EOA_ADDR.balance, 6);
        assertEq(address(_t).balance, 4);
    }

    function test_Trigger_Inadequate() public {
        _t.addCommitment(5, 2);
        vm.expectRevert(CascadingCommitment.BadTriggerMath.selector);
        _triggerSingleLevel(5);
    }

    function test_Trigger_RepeatedEntries() public {
        _t.addCommitment(5, 2);
        _t.addCommitment(5, 4);
        vm.expectRevert(
            abi.encodeWithSelector(
                CascadingCommitment.BadTrigger.selector,
                5)
        );
        uint128[] memory t = new uint128[](2);
        t[0] = 5;
        t[1] = 5;
        _t.trigger(t);
    }

    function test_Trigger_OutOfOrderEntries() public {
        _t.addCommitment(5, 2);
        _t.addCommitment(5, 4);
        _t.addCommitment(6, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                CascadingCommitment.BadTrigger.selector,
                5)
        );
        uint128[] memory t = new uint128[](2);
        t[0] = 6;
        t[1] = 5;
        _t.trigger(t);
    }

    function test_AddingCommitmentAfterWithdraw() public {
        _t.addCommitment(5, 1);
        _t.addCommitment(5, 2);
        _t.withdrawCommitment(1);
        _t.addCommitment(5, 3);

        assertEq(_t.triggerLevelWeight(5), 4);
        CommitmentForUser[] memory c = _t.commitments();
        assertEq(c.length, 2);
        assertEq(c[1].size, 3);
    }
}

// Since this inherits from the previous test, it runs all of the same cases, plus the ones we specify below.
contract CascadingCommitmentWithSizeLimitTest is CascadingCommitmentTest {
    event Stopped();

    ICascadingCommitmentWithSizeLimit internal _st;

    function setUp() public override {
        TestCascadingCommitmentWithSizeLimit c = new TestCascadingCommitmentWithSizeLimit(10);
        _t = c;
        _st = c;
        vm.startPrank(_EOA_ADDR);
    }

    function _forceSimpleStop() internal {
        _st.addCommitment(10, 10);
        _triggerSingleLevel(10);
    }

    function test_StopEvent() public {
        _t.addCommitment(10, 10);
        vm.expectEmit(false, false, false, true);
        emit Stopped();
        _triggerSingleLevel(10);
    }

    function test_AddingCommitment_AfterStop() public {
        _forceSimpleStop();
        vm.expectRevert(CascadingCommitmentWithSizeLimit.IsStopped.selector);
        _t.addCommitment(20, 5);
    }

    function test_AddingCommitment_TriggerAboveMax() public {
        vm.expectRevert(CascadingCommitmentWithSizeLimit.TriggerExceedsMax.selector);
        _t.addCommitment(200, 5);
    }

    function test_AddingCommitment_SizeAboveMax() public {
        _t.addCommitment(5, 5);
        _triggerSingleLevel(5);
        vm.expectRevert(
            abi.encodeWithSelector(
                CascadingCommitmentWithSizeLimit.SizeExceedsMax.selector,
                10, 5)
        );
        _t.addCommitment(6, 10);
    }

    function test_WithdrawingCommitment_AfterStop_NotProcessed() public {
        _st.addCommitment(5, 10);
        _st.addCommitment(5, 2);
        _triggerSingleLevel(5);
        assert(_st.stopped());
        CommitmentForUser[] memory c = _t.commitments();
        assertEq(c.length, 1);
        assertEq(c[0].triggersAt, 5);
        assertEq(c[0].size, 2);
        _st.withdrawCommitment(c[0].id);
    }

    function test_WithdrawingCommitment_AfterStop_AlreadyProcessed() public {
        _st.addCommitment(5, 9);
        _st.addCommitment(5, 2);
        _triggerSingleLevel(5);
        assert(_st.stopped());
        CommitmentForUser[] memory c = _t.commitments();
        assertEq(c.length, 1);
        assertEq(c[0].triggersAt, 5);
        assertEq(c[0].size, 1);
        _st.withdrawCommitment(c[0].id);
    }

    function test_WithdrawingCommitment_AfterStop_DifferentLevel() public {
        _st.addCommitment(5, 10);
        _st.addCommitment(3, 2);
        _triggerSingleLevel(5);
        assert(_st.stopped());
        CommitmentForUser[] memory c = _t.commitments();
        assertEq(c.length, 1);
        assertEq(c[0].triggersAt, 3);
        assertEq(c[0].size, 2);
        _st.withdrawCommitment(c[0].id);
    }

    function test_WithdrawingCommitment_AfterStop_ExactWithNc() public {
        _t.setNcPerSize(1);
        vm.deal(address(_t), 20);
        _st.addCommitment(5,5);
        _st.addCommitment(5,5);
        _st.addCommitment(5,6);
        _triggerSingleLevel(5);
        assert(_st.stopped());
        CommitmentForUser[] memory c = _t.commitments();
        assertEq(c.length, 1);
        assertEq(_EOA_ADDR.balance, 10);
        _st.withdrawCommitment(c[0].id);
        assertEq(_EOA_ADDR.balance, 16);
    }

    function test_WithdrawingCommitment_AfterStop_InexactWithNc() public {
        _t.setNcPerSize(1);
        vm.deal(address(_t), 20);
        _st.addCommitment(5,5);
        _st.addCommitment(5,6);
        _triggerSingleLevel(5);
        assert(_st.stopped());
        CommitmentForUser[] memory c = _t.commitments();
        assertEq(c.length, 1);
        assertEq(_EOA_ADDR.balance, 10);
        _st.withdrawCommitment(c[0].id);
        assertEq(_EOA_ADDR.balance, 11);
    }

    function test_Trigger_ExactStop() public {
        _st.addCommitment(5, 6);
        _st.addCommitment(5, 4);
        _triggerSingleLevel(5);
        assert(_st.stopped());
        assertEq(_st.currentSizeTotal(), 10);
    }

    function test_Trigger_InexactStop() public {
       _st.addCommitment(5, 9);
        _st.addCommitment(5, 2);
        _triggerSingleLevel(5);
        assert(_st.stopped());
        assertEq(_st.currentSizeTotal(), 10);
    }

    function test_Trigger_AfterStop() public {
        _forceSimpleStop();
        vm.expectRevert(CascadingCommitmentWithSizeLimit.IsStopped.selector);
        _triggerSingleLevel(10);
    }
}
