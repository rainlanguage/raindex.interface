// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.18;

import {IERC3156FlashLender} from "./ierc3156/IERC3156FlashLender.sol";
import {
    IInterpreterCallerV5,
    SignedContextV2,
    EvaluableV4,

    //forge-lint: disable-next-line(unused-import)
    IInterpreterV4,

    //forge-lint: disable-next-line(unused-import)
    IInterpreterStoreV3
} from "rainlang-interface-0.2.14/src/interface/IInterpreterCallerV5.sol";

import {
    ClearStateChangeV2,
    ClearConfigV2,

    //forge-lint: disable-next-line(unused-import)
    IOV2,
    OrderConfigV4,
    OrderV4
} from "./deprecated/v5/IOrderBookV5.sol";

import {Float} from "rain-math-float-0.3.10/src/lib/LibDecimalFloat.sol";

/// Evaluable run after the primary call, e.g. by governance wrappers or fee
/// collectors.
/// @param evaluable The evaluable logic to run as part of the task.
/// @param signedContext Signed context provided to the evaluable.
struct TaskV3 {
    EvaluableV4 evaluable;
    SignedContextV2[] signedContext;
}

/// @param order The order to take.
/// @param inputIOIndex Index of the order's input matched with the taker
/// output.
/// @param outputIOIndex Index of the order's output matched with the taker
/// input.
/// @param signedContext Signed context for the taken order's eval.
struct TakeOrderConfigV5 {
    OrderV4 order;
    //forge-lint: disable-next-line(mixed-case-variable)
    uint256 inputIOIndex;
    //forge-lint: disable-next-line(mixed-case-variable)
    uint256 outputIOIndex;
    SignedContextV2[] signedContext;
}

/// @param minimumIO Taker's minimum total input or output; reverts if unmet.
/// @param maximumIO Taker's maximum total input or output.
/// @param maximumIORatio Max IO ratio per order, from the order's perspective.
/// @param IOIsInput Whether `minimumIO`/`maximumIO` bound taker input or output.
/// @param orders Taken in sequence as given; no onchain sorting.
/// @param data If non-empty, `onTakeOrders2` is called on the taker with it.
struct TakeOrdersConfigV6 {
    //forge-lint: disable-next-line(mixed-case-variable)
    Float minimumIO;
    //forge-lint: disable-next-line(mixed-case-variable)
    Float maximumIO;
    //forge-lint: disable-next-line(mixed-case-variable)
    Float maximumIORatio;
    //forge-lint: disable-next-line(mixed-case-variable)
    bool IOIsInput;
    TakeOrderConfigV5[] orders;
    bytes data;
}

/// @param order The order to quote.
/// @param inputIOIndex Index of the order's input to quote.
/// @param outputIOIndex Index of the order's output to quote.
/// @param signedContext Signed context for the quoted order's eval.
struct QuoteV3 {
    OrderV4 order;
    //forge-lint: disable-next-line(mixed-case-variable)
    uint256 inputIOIndex;
    //forge-lint: disable-next-line(mixed-case-variable)
    uint256 outputIOIndex;
    SignedContextV2[] signedContext;
}

/// @title IRaindexV7
/// @notice Raindex is an order book of expression-defined orders over
/// per-owner, per-token vaults. Amounts and IO ratios (input:output) are
/// Floats, converted via the token's `decimals` only when tokens move; tokens
/// without constant `decimals` are unsupported. Clears move only internal vault
/// balances, except for vault `0` IO. Rounding favours the order.
/// REBASING, FEE-ON-TRANSFER AND OTHER DYNAMIC BALANCE TOKENS ARE NOT
/// SUPPORTED. Raindex ONLY WORKS IF TOKEN BALANCES ARE 1:1 WITH
/// ADDITION/SUBTRACTION PER VAULT MOVEMENT: vaults are credited the requested
/// amount, not the amount received, so a fee-on-transfer deposit credits more
/// than Raindex receives.
/// Orders stay live until removed. Expression storage is namespaced by order
/// owner. Interpreters and stores are untrusted. All vault balances are
/// available as zero-fee ERC3156 flash loans; `withdraw5` and `takeOrders5`
/// repay the caller's loan before sending tokens. Vault ID `0` denotes a
/// vaultless IO that moves tokens directly from or to the owner's wallet.
interface IRaindexV7 is IERC3156FlashLender, IInterpreterCallerV5 {
    error ZeroVaultId(address sender, address token);

    error ZeroDepositAmount(address sender, address token, bytes32 vaultId);

    /// Zero requested amount; a nonzero request MAY still move nothing.
    error ZeroWithdrawTargetAmount(address sender, address token, bytes32 vaultId);

    error OrderNoSources();

    error OrderNoHandleIO();

    error OrderNoInputs();

    error OrderNoOutputs();

    error ZeroMaximumIO();

    error NoOrders();

    /// An order's input and output tokens are identical.
    error TokenSelfTrade();

    event DepositV2(address sender, address token, bytes32 vaultId, uint256 depositAmountUint256);

    /// @param withdrawAmount MAY be less than `targetAmount`.
    /// @param withdrawAmountUint256 Absolute tokens moved onchain.
    event WithdrawV2(
        address sender,
        address token,
        bytes32 vaultId,
        Float targetAmount,
        Float withdrawAmount,
        uint256 withdrawAmountUint256
    );

    /// @param order Full order, to be passed back as-is to take or clear it.
    event AddOrderV3(address sender, bytes32 orderHash, OrderV4 order);

    event RemoveOrderV3(address sender, bytes32 orderHash, OrderV4 order);

    /// One per order taken. `input`/`output` are from the taker's perspective.
    event TakeOrderV4(address sender, TakeOrderConfigV5 config, Float input, Float output);

    /// The order is skipped rather than reverting the batch.
    event OrderNotFound(address sender, address owner, bytes32 orderHash);

    /// The order is skipped rather than reverting the batch.
    event OrderZeroAmount(address sender, address owner, bytes32 orderHash);

    /// The order is skipped rather than reverting the batch.
    event OrderExceedsMaxRatio(address sender, address owner, bytes32 orderHash);

    /// Emitted before calculation.
    event ClearV3(address sender, OrderV4 alice, OrderV4 bob, ClearConfigV2 clearConfig);

    event AfterClearV2(address sender, ClearStateChangeV2 clearStateChange);

    function vaultBalance2(address owner, address token, bytes32 vaultId) external view returns (Float balance);

    /// MUST NOT modify vault balances; reverts if any task reverts.
    function entask3(TaskV3[] calldata tasks) external;

    /// Deposits for `msg.sender`; no shares, balances are 1:1 with tokens.
    /// Reverts `ZeroDepositAmount` on zero amount, `ZeroVaultId` on vault `0`,
    /// or if any task reverts.
    function deposit5(address token, bytes32 vaultId, Float depositAmount, TaskV3[] calldata tasks) external;

    /// Withdraws up to `targetAmount`. Reverts `ZeroWithdrawTargetAmount` on
    /// zero target, `ZeroVaultId` on vault `0`, or if any task reverts.
    function withdraw5(address token, bytes32 vaultId, Float targetAmount, TaskV3[] calldata tasks) external;

    function orderExists(bytes32 orderHash) external view returns (bool exists);

    /// Evaluates the order with the caller as counterparty, ignoring the
    /// caller's balances. Values are Floats, not absolute token amounts.
    /// Reverts `TokenSelfTrade`. `outputMax` and `ioRatio` are `0` if the
    /// order does not exist.
    function quote3(QuoteV3 calldata quoteConfig) external view returns (bool exists, Float outputMax, Float ioRatio);

    /// Adds an order owned by `msg.sender`. Reverts `OrderNoSources`,
    /// `OrderNoHandleIO`, `OrderNoInputs`, `OrderNoOutputs`, or if any task
    /// reverts. Calculate MUST return at least max amount and IO ratio.
    /// @return stateChanged False, with no state change or event, if the order
    /// already exists.
    function addOrder5(OrderConfigV4 calldata config, TaskV3[] calldata tasks) external returns (bool stateChanged);

    /// Removes an order owned by `msg.sender`. Reverts if any task reverts.
    /// @return stateChanged False, with no state change or event, if the order
    /// is not live.
    function removeOrder4(OrderV4 calldata order, TaskV3[] calldata tasks) external returns (bool stateChanged);

    /// Takes orders in sequence until `maximumIO` is reached. Per-order
    /// failures that depend on live state are skipped with an event; static
    /// misconfiguration (e.g. token mismatch, `TokenSelfTrade`) reverts.
    /// Reverts if `minimumIO` is not reached.
    function takeOrders5(TakeOrdersConfigV6 calldata config)
        external
        returns (Float totalTakerInput, Float totalTakerOutput);

    /// Matches two live orders from different owners; the ratio spread is paid
    /// to `msg.sender`'s vaults per `clearConfig`. Reverts `TokenSelfTrade`,
    /// or if either order's input exceeds the other's output.
    /// @param aliceSignedContext Signed context for `alice`'s own eval.
    /// @param bobSignedContext Signed context for `bob`'s own eval.
    function clear4(
        OrderV4 memory alice,
        OrderV4 memory bob,
        ClearConfigV2 calldata clearConfig,
        SignedContextV2[] memory aliceSignedContext,
        SignedContextV2[] memory bobSignedContext
    ) external;
}
