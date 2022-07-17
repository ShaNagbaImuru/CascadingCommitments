// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import "./CascadingCommitment.sol";

/// @notice A cascading commitment contract for minting ERC721 tokens.
/// @dev Note that there are a number of contraints on the type of ERC721 contract that this can interface with: it must implement the enumerable extension; it must have a mint function that takes a single uint256 argument indicating how many tokens to purchase; it must have a flat mint cost per token.
contract CascadingERC721EnumerablePurchase is CascadingCommitmentWithSizeLimit, IERC721Receiver {
    error IncorrectNativeCurrencySent(uint128 neededForGas, uint128 mintCost, uint128 sent);
    error FailedMint(uint128 numToMint, uint128 mintedTotalBeforeCall, bytes returned);

    IERC721Enumerable immutable internal _nftContract;
    uint128 immutable internal _pricePerMint;
    uint128 immutable internal _baseMintNativeCurrencyForGas;
    uint128 immutable internal _perMintNativeCurrencyForGas;
    string internal _mintFnSig;

    /// @param erc721Address The address of the ERC721 contract.
    /// @param maxTokens The maximum number of tokens the ERC721 contract will issue.
    /// @param baseMintNativeCurrencyForGas The fixed gas refund amount per mint call.
    /// @param perMintNativeCurrencyForGas The gas refund amount per token minted.
    /// @param mintFnName The name of the mint function in the ERC721 contract, without args. It must be a function taking a single uint256 arg which indicates the number of tokens to mint.
    constructor(address erc721Address, uint128 maxTokens, uint128 pricePerMint, uint128 baseMintNativeCurrencyForGas, uint128 perMintNativeCurrencyForGas, string memory mintFnName)
        CascadingCommitmentWithSizeLimit(maxTokens)
    {
        _nftContract = IERC721Enumerable(erc721Address);
        _pricePerMint = pricePerMint;
        _baseMintNativeCurrencyForGas = baseMintNativeCurrencyForGas;
        _perMintNativeCurrencyForGas = perMintNativeCurrencyForGas;
        _mintFnSig = string.concat(mintFnName, "(uint256)");
    }

    function nativeCurrencyReservedForCommitmentGas(uint128 size)
        public
        override(CascadingCommitment, ICascadingCommitment)
        view
        returns (uint128)
    {
        if (size == 0) {
            return 0;
        }
        return _baseMintNativeCurrencyForGas + size * _perMintNativeCurrencyForGas;
    }

    function currentSizeTotal()
        public
        view
        override(CascadingCommitment, ICascadingCommitment)
        returns (uint128)
    {
        return uint128(_nftContract.totalSupply());
    }

    function onERC721Received(address, address, uint256, bytes memory)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _checkCommitment(uint128 size)
        internal
        override
    {
        uint128 nativeCurrencyForGas = nativeCurrencyReservedForCommitmentGas(size);
        uint128 nativeCurrencyForPurchase = _pricePerMint * size;
        if (msg.value != nativeCurrencyForGas + nativeCurrencyForPurchase) {
            revert IncorrectNativeCurrencySent(nativeCurrencyForGas, nativeCurrencyForPurchase, uint128(msg.value));
        }
    }

    function _processCommitment(CommitmentInLevel memory commitment, uint128 numMinted)
        internal
        override
        returns (uint128 sizeProcessed)
    {
        uint128 numToMint = commitment.size;
        if (numMinted + numToMint > maxSizeTotal) {
            numToMint = maxSizeTotal - numMinted;
        }
        (bool mintSuccess, bytes memory returned) = address(_nftContract).call{
                value: numToMint * _pricePerMint
            }
            (abi.encodeWithSignature(_mintFnSig, numToMint));
        if (!mintSuccess) {
            revert FailedMint(numToMint, numMinted, returned);
        }
        uint256 numHeld = _nftContract.balanceOf(address(this));
        for (uint256 i = 0; i < numHeld; i++) {
            _nftContract.safeTransferFrom(
                address(this),
                commitment.committer,
                _nftContract.tokenOfOwnerByIndex(address(this), 0));
        }
        return numToMint;
    }

    function _refundCommitment(uint128 size, bool isStoppedOn)
        internal
        override
    {
        if (!isStoppedOn) {
            payable(msg.sender).transfer(nativeCurrencyReservedForCommitmentGas(size) + _pricePerMint * size);
        } else {
            payable(msg.sender).transfer(_nativeCurrencyForStopItem + _pricePerMint * size);
        }
    }
}
