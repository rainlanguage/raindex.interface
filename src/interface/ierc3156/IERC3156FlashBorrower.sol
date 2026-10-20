// SPDX-License-Identifier: CC0-1.0
// SPDX-FileCopyrightText: Alberto Cuesta Cañada, Fiona Kobayashi, fubuloubu, Austin Williams, "EIP-3156: Flash Loans," Ethereum Improvement Proposals, no. 3156, November 2020. [Online serial]. Available: https://eips.ethereum.org/EIPS/eip-3156.
pragma solidity ^0.8.18;

bytes32 constant ON_FLASH_LOAN_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

interface IERC3156FlashBorrower {
    /// @return `ON_FLASH_LOAN_CALLBACK_SUCCESS` on success.
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32);
}
