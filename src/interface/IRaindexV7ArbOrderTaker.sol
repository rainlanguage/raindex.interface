// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.18;

import {IRaindexV7OrderTaker} from "./IRaindexV7OrderTaker.sol";
import {TakeOrdersConfigV6, IRaindexV7, TaskV3} from "./IRaindexV7.sol";

interface IRaindexV7ArbOrderTaker is IRaindexV7OrderTaker {
    /// Takes orders on `raindex` then runs `task`. Implementations MUST
    /// validate that `raindex` is trusted.
    function arb6(IRaindexV7 raindex, TakeOrdersConfigV6 calldata takeOrders, TaskV3 calldata task) external payable;
}
