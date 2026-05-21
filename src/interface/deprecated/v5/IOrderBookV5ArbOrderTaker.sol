// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.18;

import {IOrderBookV5OrderTaker} from "./IOrderBookV5OrderTaker.sol";
import {
    TakeOrdersConfigV4,
    IOrderBookV5,
    TaskV2,

    //forge-lint: disable-next-line(unused-import)
    EvaluableV4
} from "./IOrderBookV5.sol";

/// @title IOrderBookV5ArbOrderTaker
/// @notice Interface for contracts that execute arbitrage against an
/// `IOrderBookV5` orderbook by taking orders and executing a post-arb task.
interface IOrderBookV5ArbOrderTaker is IOrderBookV5OrderTaker {
    /// Executes an arbitrage against the given orderbook. The `msg.value` MAY
    /// be used by the implementation to wrap native tokens or interact with
    /// external liquidity sources. Implementations MUST validate that
    /// `orderBook` is a trusted contract.
    /// @param orderBook The orderbook to arb against.
    /// @param takeOrders Config for the orders to take.
    /// @param task Post-arb task to evaluate.
    function arb4(IOrderBookV5 orderBook, TakeOrdersConfigV4 calldata takeOrders, TaskV2 calldata task) external payable;
}
