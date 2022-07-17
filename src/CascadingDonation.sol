// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./CascadingCommitment.sol";

/// @notice A cascading commitment contract for donating native currency (e.g. ether) to an address. NOTE: this checks the current balance of the address for triggering, not just donations from this contract.
contract CascadingNativeDonation is CascadingCommitment {
    error IncorrectNativeCurrencySent(uint128 neededForGas, uint128 promisedDonation, uint128 sent);

    address payable immutable public donationAddress;
    uint128 immutable internal _nativeCurrencyForTransfer;

    /// @param donationAddr The address to which the currency will be donated.
    /// @param nativeCurrencyForTransfer How much currency is expected to pay for the gas of one transfer (regardless of size).
    constructor(address payable donationAddr, uint128 nativeCurrencyForTransfer) {
        donationAddress = donationAddr;
        _nativeCurrencyForTransfer = nativeCurrencyForTransfer;
    }

    function nativeCurrencyReservedForCommitmentGas(uint128)
        public
        override
        view
        returns (uint128)
    {
        return _nativeCurrencyForTransfer;
    }

    function currentSizeTotal()
        public
        override
        view
        returns (uint128)
    {
        return uint128(donationAddress.balance);
    }

    function _checkCommitment(uint128 size)
        internal
        override
    {
        if (msg.value != size + _nativeCurrencyForTransfer) {
            revert IncorrectNativeCurrencySent(_nativeCurrencyForTransfer, size, uint128(msg.value));
        }
    }

    function _processCommitment(CommitmentInLevel memory commitment)
        internal
        override
    {
        donationAddress.transfer(commitment.size);
    }

    function _refundCommitment(uint128 size)
        internal
        override
    {
        payable(msg.sender).transfer(size + _nativeCurrencyForTransfer);
    }
}

/// @notice A cascading commitment contract for donating ERC20 tokens (e.g. USDC) to an address. NOTE: this checks the current balance of the address for triggering, not just donations from this contract.
contract CascadingERC20Donation is CascadingCommitment {
    error IncorrectNativeCurrencySent(uint128 neededForGas, uint128 sent);

    address payable immutable public donationAddress;
    IERC20 immutable public currencyAddress;
    uint128 immutable internal _nativeCurrencyForTransfer;

    /// @param donationAddr The address to which the currency will be donated.
    /// @param currencyAddr The address of the ERC20 token in which donations are denominated.
    /// @param nativeCurrencyForTransfer How much currency is expected to pay for the gas of one transfer (regardless of size).
    constructor(address payable donationAddr, address currencyAddr, uint128 nativeCurrencyForTransfer) {
        donationAddress = donationAddr;
        currencyAddress = IERC20(currencyAddr);
        _nativeCurrencyForTransfer = nativeCurrencyForTransfer;
    }

    function nativeCurrencyReservedForCommitmentGas(uint128)
        public
        override
        view
        returns (uint128)
    {
        return _nativeCurrencyForTransfer;
    }

    function currentSizeTotal()
        public
        override
        view
        returns (uint128)
    {
        return uint128(currencyAddress.balanceOf(donationAddress));
    }

    /// @dev We transfer the ERC20 tokens in this check.
    function _checkCommitment(uint128 size)
        internal
        override
    {
        if (msg.value != _nativeCurrencyForTransfer) {
            revert IncorrectNativeCurrencySent(_nativeCurrencyForTransfer, uint128(msg.value));
        }
        currencyAddress.transferFrom(msg.sender, address(this), size);
    }

    function _processCommitment(CommitmentInLevel memory commitment)
        internal
        override
    {
        currencyAddress.transfer(donationAddress, commitment.size);
    }

    function _refundCommitment(uint128 size)
        internal
        override
    {
        currencyAddress.transfer(msg.sender, size);
        payable(msg.sender).transfer(_nativeCurrencyForTransfer);
    }
}