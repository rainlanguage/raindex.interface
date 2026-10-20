// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.18;

import {Float} from "./IRaindexV6.sol";

interface IRaindexV6OrderTaker {
    /// Called by `takeOrders4` when its `data` is non-empty and input is
    /// nonzero, after input is sent (net of any flash loan debt) and before
    /// output is pulled. Implementations MUST validate `msg.sender` and MUST
    /// NOT re-enter the Raindex.
    function onTakeOrders2(
        address inputToken,
        address outputToken,
        Float inputAmountSent,
        Float totalOutputAmount,
        bytes calldata takeOrdersData
    ) external;
}
