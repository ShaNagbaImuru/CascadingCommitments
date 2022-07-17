// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./ICascadingCommitment.sol";

/// @notice A base implementation of cascading commitments.
abstract contract CascadingCommitment is ICascadingCommitment {
    // Represents a commitment inside a trigger level; holds only information needed to process.
    struct CommitmentInLevel {
        address committer;
        uint128 size;
    }

    // A trigger level, holding a couple of bookkeeping variables and all the associated commitments.
    struct TriggerLevel {
         uint128 totalSize;
         uint128 totalNativeCurrencyForGas;
        CommitmentInLevel[] commitments;
    }

    // A pointer to a given commitment.
    struct _CommitmentReference {
        uint128 triggerLevel;
        uint32 index;
    }

    /// @notice Emitted when a trigger level is added to or withdrawn from.
    event TriggerLevelSizeChange(uint128 level, uint128 newSize);
    /// @notice Emitted when a level is triggered.
    event Triggered(uint128 level);

    error BadId();
    error BadSize();
    error AlreadyTriggered();
    error BadTrigger(uint128 trigger);
    // Used when the passed trigger levels are not eligible to trigger due to insufficient total size.
    error BadTriggerMath();

    mapping(uint128 => TriggerLevel) public triggerLevels;
    mapping(address => _CommitmentReference[]) internal _commitmentsByUser;

    /// @inheritdoc ICascadingCommitment
    function addCommitment(uint128 triggersAt, uint128 commitmentSize)
        public
        payable
        virtual
    {
        if (triggersAt <= currentSizeTotal()) {
            revert AlreadyTriggered();
        }
        if (commitmentSize == 0) {
            revert BadSize();
        }
        _checkCommitment(commitmentSize);
        TriggerLevel storage l = triggerLevels[triggersAt];
        l.totalSize += commitmentSize;
        l.totalNativeCurrencyForGas += nativeCurrencyReservedForCommitmentGas(commitmentSize);
        l.commitments.push(CommitmentInLevel({committer: msg.sender, size: commitmentSize}));
        emit TriggerLevelSizeChange(triggersAt, l.totalSize);
        _commitmentsByUser[msg.sender].push(_CommitmentReference({triggerLevel: triggersAt, index: uint32(l.commitments.length - 1)}));
    }

    /// @inheritdoc ICascadingCommitment
    function withdrawCommitment(uint256 id)
        external
        virtual
    {
        _CommitmentReference memory ref = _commitmentsByUser[msg.sender][id];
        if (!_validCommitment(ref)) {
            revert BadId();
        }
        uint128 size = triggerLevels[ref.triggerLevel].commitments[ref.index].size;
        assert(size != 0);
        triggerLevels[ref.triggerLevel].totalSize -= size;
        emit TriggerLevelSizeChange(ref.triggerLevel, triggerLevels[ref.triggerLevel].totalSize);
        delete triggerLevels[ref.triggerLevel].commitments[ref.index];
        delete _commitmentsByUser[msg.sender][id];
        _refundCommitment(size);
    }

    /// @inheritdoc ICascadingCommitment
    function trigger(uint128[] calldata levels)
        external
        virtual
    {
        uint128 total = currentSizeTotal();
        uint256 lastLevel = 0;  // used for monotonicity check
        uint256 accumulatedRefund = 0;

        for (uint256 i = 0; i < levels.length; i++) {
            uint128 t = levels[i];
            if (t == 0 || t <= lastLevel) {
                revert BadTrigger(t);
            }
            lastLevel = t;
            total += triggerLevels[t].totalSize;
            TriggerLevel memory level = triggerLevels[t];

            for (uint256 j = 0; j < level.commitments.length; j++) {
                _processCommitment(level.commitments[j]);
            }
            accumulatedRefund += triggerLevels[t].totalNativeCurrencyForGas;
            delete triggerLevels[t];
            emit Triggered(t);
        }
        if (total < levels[levels.length - 1]) {
            revert BadTriggerMath();
        }
        payable(msg.sender).transfer(accumulatedRefund);  // reentry is possible here, but should be safe.
    }

    /// @inheritdoc ICascadingCommitment
    function commitments()
        external
        view
        returns (CommitmentForUser[] memory)
    {
        // We need to first walk the reference list and find how many entries have not been processed.
        uint256 validEntries = 0;
        for (uint256 i = 0; i < _commitmentsByUser[msg.sender].length; i++) {
            if (_validCommitment(_commitmentsByUser[msg.sender][i])) {
                validEntries += 1;
            }
        }

        // TODO: check if we can save substantial gas by walking the commitments only once.
        CommitmentForUser[] memory userCommitments = new CommitmentForUser[](validEntries);
        uint256 idx = 0;
        for (uint256 i = 0; i < _commitmentsByUser[msg.sender].length; i++) {
            _CommitmentReference storage ref = _commitmentsByUser[msg.sender][i];
            if (_validCommitment(ref)) {
                userCommitments[idx] = CommitmentForUser({
                    triggersAt: ref.triggerLevel,
                    size: triggerLevels[ref.triggerLevel].commitments[ref.index].size,
                    id: i
                });
                idx += 1;
            }
        }
        return userCommitments;
    }

    /// @inheritdoc ICascadingCommitment
    function currentSizeTotal() public view virtual returns (uint128);

    /// @inheritdoc ICascadingCommitment
    function nativeCurrencyReservedForCommitmentGas(uint128 size) public virtual returns (uint128);

    /// @notice Checks whether a passed commitment is valid (i.e. unprocessed).
    function _validCommitment(_CommitmentReference memory ref)
        internal
        view
        virtual
        returns (bool)
    {
        // a deleted reference will be zeroed; trigger level 0 is never valid.
        return ref.triggerLevel != 0;
    }

    /// @notice Checks whether the proposed commitment should be accepted. In particular, it must at least check if sufficient native currency was passed to pay for later gas.
    /// @dev This function should revert if the proposed commitment should not be accepted.
    function _checkCommitment(uint128 size) internal virtual;

    /// @notice Process (carry out) the given commitment.
    function _processCommitment(CommitmentInLevel memory commitment) internal virtual;

    /// @notice Refund a commitment of the given size to the caller.
    function _refundCommitment(uint128 size) internal virtual;
}

/// @notice A base implementation of cascading commitments with limited accepted size. After that size is reached, only withdrawing commitments is allowed. NOTE that commitments may be only partially processed if they would cause us to exceed the max size.
abstract contract CascadingCommitmentWithSizeLimit is ICascadingCommitmentWithSizeLimit, CascadingCommitment {
    /// @notice Emitted when the contract enters a stopped state because the max size hss been reached.
    event Stopped();

    error IsStopped();
    error TriggerExceedsMax();
    error SizeExceedsMax(uint128 requested, uint128 remaining);

    modifier ifNotStopped() {
        if (stopped()) {
            revert IsStopped();
        }
        _;
    }

    uint128 public immutable maxSizeTotal;
    // When we stop in the middle of processing an item, this tracks the native currency needed to
    // refund gas costs for the remainder of that item.
    uint128 internal _nativeCurrencyForStopItem;
    // A reference to the last item processed before the contract stopped.
    _CommitmentReference internal _stoppedAfterProcessing;

    constructor(uint128 maxSize)
    {
        maxSizeTotal = maxSize;
    }

    /// @inheritdoc CascadingCommitment
    function addCommitment(uint128 triggersAt, uint128 commitmentSize)
        public
        payable
        virtual
        override(ICascadingCommitment, CascadingCommitment)
        ifNotStopped
    {
        if (triggersAt > maxSizeTotal) {
            revert TriggerExceedsMax();
        }
        uint128 remaining = maxSizeTotal - currentSizeTotal();
        if (commitmentSize > remaining) {
            revert SizeExceedsMax(commitmentSize, remaining);
        }
        super.addCommitment(triggersAt, commitmentSize);
    }

    /// @inheritdoc CascadingCommitment
    /// @dev This is quite similar to the base version, but calls a different _refundCommitment that accepts a parameter indicating if the refund is for the last item processed before stop.
    function withdrawCommitment(uint256 id)
        external
        override (CascadingCommitment, ICascadingCommitment)
        virtual
    {
        _CommitmentReference memory ref = _commitmentsByUser[msg.sender][id];
        if (!_validCommitment(ref)) {
            revert BadId();
        }
        uint128 size = triggerLevels[ref.triggerLevel].commitments[ref.index].size;
        assert(size != 0);
        triggerLevels[ref.triggerLevel].totalSize -= size;
        emit TriggerLevelSizeChange(ref.triggerLevel, triggerLevels[ref.triggerLevel].totalSize);
        delete triggerLevels[ref.triggerLevel].commitments[ref.index];
        delete _commitmentsByUser[msg.sender][id];
        _refundCommitment(size,
            ref.triggerLevel == _stoppedAfterProcessing.triggerLevel && ref.index == _stoppedAfterProcessing.index);
    }

    /// @inheritdoc CascadingCommitment
    function trigger(uint128[] calldata levels)
        external
        override(CascadingCommitment, ICascadingCommitment)
        ifNotStopped
    {
        uint128 total = currentSizeTotal();
        uint256 lastLevel = 0;
        uint256 accumulatedRefund = 0;

        for (uint256 i = 0; i < levels.length; i++) {
            uint128 t = levels[i];
            if (t == 0 || t <= lastLevel) {
                revert BadTrigger(t);
            }
            emit Triggered(t);
            lastLevel = t;
            uint128 levelSize = triggerLevels[t].totalSize;
            TriggerLevel memory level = triggerLevels[t];
            if (total + levelSize >= maxSizeTotal) {
                // A stop should occur somewhere in this level (possibly after the last item).
                for (uint256 j = 0; j < level.commitments.length; j++) {
                    uint128 sizeProcessed = _processCommitment(level.commitments[j], total);
                    accumulatedRefund += nativeCurrencyReservedForCommitmentGas(sizeProcessed);
                    total += sizeProcessed;
                    if (total >= maxSizeTotal) {  // We will stop here.
                        _nativeCurrencyForStopItem = nativeCurrencyReservedForCommitmentGas(level.commitments[j].size) - nativeCurrencyReservedForCommitmentGas(sizeProcessed);
                        triggerLevels[t].commitments[j].size -= sizeProcessed;
                        _stoppedAfterProcessing.triggerLevel = t;
                        _stoppedAfterProcessing.index = uint32(j);
                        if (triggerLevels[t].commitments[j].size == 0) {
                            // If we exactly hit the total by fully processing this item, bump the reference index.
                            _stoppedAfterProcessing.index += 1;
                            if (_stoppedAfterProcessing.index < level.commitments.length) {
                                _nativeCurrencyForStopItem = nativeCurrencyReservedForCommitmentGas(level.commitments[_stoppedAfterProcessing.index].size);
                            }
                        }
                        emit Stopped();
                        break;
                    }
                }
            } else {
                // No stop will occur in this level, so we can handle it simply.
                for (uint256 j = 0; j < level.commitments.length; j++) {
                    _processCommitment(level.commitments[j], total);
                }
                total += level.totalSize;
                accumulatedRefund += triggerLevels[t].totalNativeCurrencyForGas;
                delete triggerLevels[t];
            }
        }
        if (total < levels[levels.length - 1]) {
            revert BadTriggerMath();
        }
        payable(msg.sender).transfer(accumulatedRefund);
    }

    /// @dev Checks whether the reference to the last processed item has been set to decide if a stop occurred.
    function stopped()
        public
        view
        returns (bool)
    {
        return _stoppedAfterProcessing.triggerLevel != 0;
    }

    function _validCommitment(_CommitmentReference memory ref)
        internal
        view
        virtual
        override
        returns (bool)
    {
        if (ref.triggerLevel == 0) {
            return false;
        }
        // every reference before this point has already been processed and is thus not valid
        if (ref.triggerLevel == _stoppedAfterProcessing.triggerLevel && ref.index < _stoppedAfterProcessing.index) {
            return false;
        }
        return true;
    }

    /// @dev We pass an extra bool here so the precalculated refund amount for the partially-processed item can be used.
    function _refundCommitment(uint128 size, bool isStoppedOn) internal virtual;

    function _refundCommitment(uint128) internal override pure {
        assert(false);
    }

    /// @dev We pass the size so that we can successfully partially process the commitment if needed.
    function _processCommitment(CommitmentInLevel memory commitment, uint128 totalSizeBeforeProcessing)
        internal
        virtual
        returns (uint128 sizeProcessed);

    function _processCommitment(CommitmentInLevel memory)
        internal
        override
        pure
    {
        assert(false);
    }
}