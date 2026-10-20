// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.18;

import {IRaindexV6OrderTaker} from "./IRaindexV6OrderTaker.sol";
import {TakeOrdersConfigV5, IRaindexV6, TaskV2} from "./IRaindexV6.sol";

interface IRaindexV6ArbOrderTaker is IRaindexV6OrderTaker {
    /// Takes orders on `raindex` then runs `task`. Implementations MUST
    /// validate that `raindex` is trusted.
    function arb5(IRaindexV6 raindex, TakeOrdersConfigV5 calldata takeOrders, TaskV2 calldata task) external payable;
}
