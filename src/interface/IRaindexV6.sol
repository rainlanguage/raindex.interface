// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity ^0.8.18;

import {IERC3156FlashLender} from "./ierc3156/IERC3156FlashLender.sol";
import {
    IInterpreterCallerV4,
    SignedContextV1,

    //forge-lint: disable-next-line(unused-import)
    EvaluableV4,

    //forge-lint: disable-next-line(unused-import)
    IInterpreterV4,

    //forge-lint: disable-next-line(unused-import)
    IInterpreterStoreV3
} from "rain-interpreter-interface-0.1.0/src/interface/IInterpreterCallerV4.sol";

/// Import unmodified structures from older versions of the Raindex interface.
import {
    ClearStateChangeV2,
    ClearConfigV2,
    TaskV2,

    //forge-lint: disable-next-line(unused-import)
    IOV2,
    OrderConfigV4,
    OrderV4,
    TakeOrderConfigV4,
    QuoteV2
} from "./deprecated/v5/IOrderBookV5.sol";

import {Float} from "rain-math-float-0.1.1/src/lib/LibDecimalFloat.sol";

/// Config for a list of orders to take sequentially as part of a `takeOrders`
/// call.
/// @param minimumInput Minimum input/output from the perspective of the order
/// taker.
/// @param maximumInput Maximum input/output from the perspective of the order
/// taker.
/// @param maximumIORatio Maximum IO ratio as calculated by the order being
/// taken. The input is from the perspective of the order so higher ratio means
/// worse deal for the order taker.
/// @param IOIsInput If true, the minimum and maximum amounts are the input from
/// the perspective of the order taker. If false, they are the output.
/// @param orders Ordered list of orders that will be taken until the limit is
/// hit. Takers are expected to prioritise orders that appear to be offering
/// better deals i.e. lower IO ratios. This prioritisation and sorting MUST
/// happen offchain, e.g. via. some simulator.
/// @param data If nonzero length, triggers `onTakeOrders` on the caller of
/// `takeOrders` with this data. This allows the caller to perform arbitrary
/// onchain actions between receiving their input tokens, before having to send
/// their output tokens.
struct TakeOrdersConfigV5 {
    //forge-lint: disable-next-line(mixed-case-variable)
    Float minimumIO;
    //forge-lint: disable-next-line(mixed-case-variable)
    Float maximumIO;
    //forge-lint: disable-next-line(mixed-case-variable)
    Float maximumIORatio;
    //forge-lint: disable-next-line(mixed-case-variable)
    bool IOIsInput;
    TakeOrderConfigV4[] orders;
    bytes data;
}

/// @title IRaindexV6
/// @notice A Raindex that deploys _strategies_ represented as interpreter
/// expressions rather than individual orders. The Raindex contract itself
/// behaves similarly to an `ERC4626` vault but with much more fine grained
/// control over how tokens are allocated and moved internally by their owners,
/// and without any concept of "shares". Token owners MAY deposit and withdraw
/// their tokens under arbitrary vault IDs on a per-token basis, then define
/// orders that specify how tokens move between vaults according to an expression.
/// The expression returns a maximum amount and a token input/output ratio from
/// the perpective of the order. When two expressions intersect, as in their
/// ratios are the inverse of each other, then tokens can move between vaults.
///
/// For example, consider order A with input TKNA and output TKNB with a constant
/// ratio of 100:1. This order in isolation has no ability to move tokens. If
/// an order B appears with input TKNB and output TKNA and a ratio of 1:100 then
/// this is a perfect match with order A. In this case 100 TKNA will move from
/// order B to order A and 1 TKNB will move from order A to order B.
///
/// IO ratios are always specified as input:output and are rain floating point
/// values. The maximum amount that can be moved in the current clearance is also
/// set by the order expression as a rain floating point value.
///
/// Typically orders will not clear when their match is exactly 1:1 as the
/// clearer needs to pay gas to process the match. Each order will get exactly
/// the ratio it calculates when it does clear so if there is _overlap_ in the
/// ratios then the clearer keeps the difference. In our above example, consider
/// order B asking a ratio of 1:110 instead of 1:100. In this case 100 TKNA will
/// move from order B to order A and 10 TKNA will move to the clearer's vault and
/// 1 TKNB will move from order A to order B. In the case of fixed prices this is
/// not very interesting as order B could more simply take order A directly for
/// cheaper rather than involving a third party. Indeed, Raindex supports a
/// direct "take orders" method that works similar to a "market buy". In the case
/// of dynamic expression based ratios, it allows both order A and order B to
/// clear non-interactively according to their strategy, trading off active
/// management, dealing with front-running, MEV, etc. for zero-gas and
/// exact-ratio clearance.
///
/// The general invariant for clearing and take orders is:
///
/// ```
/// ratioA = InputA / OutputA
/// ratioB = InputB / OutputB
/// ratioA * ratioB = ( InputA * InputB ) / ( OutputA * OutputB )
/// OutputA >= InputB
/// OutputB >= InputA
///
/// ∴ ratioA * ratioB <= 1
/// ```
///
/// Raindex is `IERC3156FlashLender` compliant with a 0 fee flash loan
/// implementation to allow external liquidity from other onchain DEXes to match
/// against Raindex expressions. All deposited tokens across all vaults are
/// available for flashloan, the flashloan MAY BE REPAID BY CALLING TAKE ORDER
/// such that Raindex's liability to its vaults is decreased by an incoming
/// trade from the flashloan borrower.
///
/// Token amounts and ratios returned by calculate order MUST be rain floating
/// point values. Handle IO will receive these values as floating point values.
/// As token amounts are floats internally, they can represent any decimals that
/// the token might have. The _precision_ of the floating point values is capped
/// at 37 decimals generally because when packed the floats are normalized to
/// int128 values for the coefficients. Generally this means that the precision
/// is larger than the entire minted supply of almost all tokens in existence.
/// In the rare case of a token that has token balances in the Raindex larger
/// than 10^38, some truncation will occur after the 37th decimal place
/// internally, on the _least_ significant digits, so should not be an issue
/// even in extreme edge cases.
///
/// Internal float values are converted to absolute token values according to the
/// token's own `decimals` call only when tokens are moved by the Raindex. This
/// means that some tokens MAY NOT be supported:
/// - If the token does not implement `decimals` then the Raindex will revert
///   when trying to move tokens.
/// - If the token has a `decimals` value that is not a constant value then the
///   internal accounting will be incorrect and the Raindex will either be
///   drained of or lock up that token. (other tokens will not be impacted).
///
/// When two orders clear there are NO TOKEN MOVEMENTS, only internal vault
/// balances are updated from the input and output vaults. Typically this results
/// in less gas per clear than calling external token transfers and also avoids
/// issues with reentrancy, allowances, external balances etc. This also means
/// that REBASING TOKENS AND TOKENS WITH DYNAMIC BALANCE ARE NOT SUPPORTED.
/// Raindex ONLY WORKS IF TOKEN BALANCES ARE 1:1 WITH ADDITION/SUBTRACTION PER
/// VAULT MOVEMENT.
///
/// Dust due to rounding errors always favours the order. Output max is rounded
/// down and IO ratios are rounded up. Input and output amounts are always
/// converted to absolute values before applying to vault balances such that
/// Raindex always retains fully collateralised inventory of underlying token
/// balances to support withdrawals, with the caveat that dynamic token balances
/// are not supported.
///
/// When an order clears it is NOT removed. Orders remain active until the owner
/// deactivates them. This is gas efficient as order owners MAY deposit more
/// tokens in a vault with an order against it many times and the order strategy
/// will continue to be clearable according to its expression. As vault IDs are
/// `bytes` values there are effectively infinite possible vaults for any token
/// so there is no limit to how many active orders any address can have at one
/// time. This also allows orders to be daisy chained arbitrarily where output
/// vaults for some order are the input vaults for some other order.
///
/// Expression storage is namespaced by order owner, so gets and sets are unique
/// to each onchain address. Order owners MUST TAKE CARE not to override their
/// storage sets globally across all their orders, which they can do most simply
/// by hashing the order hash into their get/set keys inside the expression. This
/// gives maximum flexibility for shared state across orders without allowing
/// order owners to attack and overwrite values stored by orders placed by their
/// counterparty.
///
/// Note that each order specifies its own interpreter and deployer so the
/// owner is responsible for not corrupting their own calculations with bad
/// interpreters. This also means the Raindex MUST assume the interpreter, and
/// notably the interpreter's store, is malicious and guard against reentrancy
/// etc.
///
/// As Raindex supports any expression that can run on any `IInterpreterV4` and
/// counterparties are available to the order, order strategies are free to
/// implement KYC/membership, tracking, distributions, stock, buybacks, etc. etc.
///
/// Main differences between `IOrderBookV5` and `IRaindexV6`:
/// - Supports vaultless orders.
/// - Supports take order configuration based on taker output rather than input.
interface IRaindexV6 is IERC3156FlashLender, IInterpreterCallerV4 {
    /// MUST be thrown by `deposit` and `withdraw` if the vault ID is zero.
    /// @param sender `msg.sender` depositing or withdrawing tokens.
    /// @param token The token being deposited or withdrawn.
    error ZeroVaultId(address sender, address token);

    /// MUST be thrown by `deposit` if the amount is zero.
    /// @param sender `msg.sender` depositing tokens.
    /// @param token The token being deposited.
    /// @param vaultId The vault ID the tokens are being deposited under.
    error ZeroDepositAmount(address sender, address token, bytes32 vaultId);

    /// MUST be thrown by `withdraw` if the amount _requested_ to withdraw is
    /// zero. The withdrawal MAY still not move any tokens if the vault balance
    /// is zero, or the withdrawal is used to repay a flash loan.
    /// @param sender `msg.sender` withdrawing tokens.
    /// @param token The token being withdrawn.
    /// @param vaultId The vault ID the tokens are being withdrawn from.
    error ZeroWithdrawTargetAmount(address sender, address token, bytes32 vaultId);

    /// MUST be thrown by `addOrder` if the order has no associated calculation.
    error OrderNoSources();

    /// MUST be thrown by `addOrder` if the order has no associated handle IO.
    error OrderNoHandleIO();

    /// MUST be thrown by `addOrder` if the order has no inputs.
    error OrderNoInputs();

    /// MUST be thrown by `addOrder` if the order has no outputs.
    error OrderNoOutputs();

    /// MUST be thrown by `takeOrders` if the maximum input/output is zero.
    error ZeroMaximumIO();

    /// MUST be thrown when take orders is called with no orders.
    error NoOrders();

    /// Some tokens have been deposited to a vault.
    /// @param sender `msg.sender` depositing tokens. Delegated deposits are NOT
    /// supported.
    /// @param token The token being deposited.
    /// @param vaultId The vault ID the tokens are being deposited under.
    /// @param depositAmountUint256 The amount of tokens deposited.
    event DepositV2(address sender, address token, bytes32 vaultId, uint256 depositAmountUint256);

    /// Some tokens have been withdrawn from a vault.
    /// @param sender `msg.sender` withdrawing tokens. Delegated withdrawals are
    /// NOT supported.
    /// @param token The token being withdrawn.
    /// @param vaultId The vault ID the tokens are being withdrawn from.
    /// @param targetAmount The amount of tokens requested to withdraw.
    /// @param withdrawAmount The amount of tokens withdrawn, can be less
    /// than the target amount if the vault does not have the funds available to
    /// cover the target amount. For example an active order might move tokens
    /// before the withdraw completes.
    /// @param withdrawAmountUint256 The amount of tokens withdrawn, as the
    /// uint256 of tokens that actually move onchain.
    event WithdrawV2(
        address sender,
        address token,
        bytes32 vaultId,
        Float targetAmount,
        Float withdrawAmount,
        uint256 withdrawAmountUint256
    );

    /// An order has been added to the Raindex. The order is permanently and
    /// always active according to its expression until/unless it is removed.
    /// @param sender `msg.sender` adding the order and is owner of the order.
    /// @param orderHash The hash of the order as it is recorded onchain. Only
    /// the hash is stored in Raindex storage to avoid paying gas to store the
    /// entire order.
    /// @param order The newly added order. MUST be handed back as-is when
    /// clearing orders and contains derived information in addition to the order
    /// config that was provided by the order owner.
    event AddOrderV3(address sender, bytes32 orderHash, OrderV4 order);

    /// An order has been removed from the Raindex. This effectively
    /// deactivates it. Orders can be added again after removal.
    /// @param sender `msg.sender` removing the order and is owner of the order.
    /// @param orderHash The hash of the removed order.
    /// @param order The removed order.
    event RemoveOrderV3(address sender, bytes32 orderHash, OrderV4 order);

    /// Some order has been taken by `msg.sender`. This is the same as them
    /// placing inverse orders then immediately clearing them all, but costs less
    /// gas and is more convenient and reliable. Analogous to a market buy
    /// against the specified orders. Each order that is matched within a the
    /// `takeOrders` loop emits its own individual event.
    /// @param sender `msg.sender` taking the orders.
    /// @param config All config defining the orders to attempt to take.
    /// @param input The input amount from the perspective of sender.
    /// @param output The output amount from the perspective of sender.
    event TakeOrderV3(address sender, TakeOrderConfigV4 config, Float input, Float output);

    /// Emitted when attempting to match an order that either never existed or
    /// was removed. An event rather than an error so that we allow attempting
    /// many orders in a loop and NOT rollback on "best effort" basis to clear.
    /// @param sender `msg.sender` clearing the order that wasn't found.
    /// @param owner Owner of the order that was not found.
    /// @param orderHash Hash of the order that was not found.
    event OrderNotFound(address sender, address owner, bytes32 orderHash);

    /// Emitted when an order evaluates to a zero amount. An event rather than an
    /// error so that we allow attempting many orders in a loop and NOT rollback
    /// on a "best effort" basis to clear.
    /// @param sender `msg.sender` clearing the order that had a 0 amount.
    /// @param owner Owner of the order that evaluated to a 0 amount.
    /// @param orderHash Hash of the order that evaluated to a 0 amount.
    event OrderZeroAmount(address sender, address owner, bytes32 orderHash);

    /// Emitted when an order evaluates to a ratio exceeding the counterparty's
    /// maximum limit. An event rather than an error so that we allow attempting
    /// many orders in a loop and NOT rollback on a "best effort" basis to clear.
    /// @param sender `msg.sender` clearing the order that had an excess ratio.
    /// @param owner Owner of the order that had an excess ratio.
    /// @param orderHash Hash of the order that had an excess ratio.
    event OrderExceedsMaxRatio(address sender, address owner, bytes32 orderHash);

    /// Emitted before two orders clear. Covers both orders and includes all the
    /// state before anything is calculated.
    /// @param sender `msg.sender` clearing both orders.
    /// @param alice One of the orders.
    /// @param bob The other order.
    /// @param clearConfig Additional config required to process the clearance.
    event ClearV3(address sender, OrderV4 alice, OrderV4 bob, ClearConfigV2 clearConfig);

    /// Emitted after two orders clear. Includes all final state changes in the
    /// vault balances, including the clearer's vaults.
    /// @param sender `msg.sender` clearing the order.
    /// @param clearStateChange The final vault state changes from the clearance.
    event AfterClearV2(address sender, ClearStateChangeV2 clearStateChange);

    /// Get the current balance of a vault for a given owner, token and vault ID.
    /// @param owner The owner of the vault.
    /// @param token The token the vault is for.
    /// @param vaultId The vault ID to read.
    /// @return balance The current balance of the vault.
    function vaultBalance2(address owner, address token, bytes32 vaultId) external view returns (Float balance);

    /// `msg.sender` entasks the provided tasks. This DOES NOT return
    /// any values, and MUST NOT modify any vault balances. Presumably the
    /// expressions will modify some internal state associated with active
    /// orders. If ANY of the expressions revert, the entire transaction MUST
    /// revert.
    /// @param tasks The tasks to evaluate.
    function entask2(TaskV2[] calldata tasks) external;

    /// `msg.sender` deposits tokens according to config. The config specifies
    /// the vault to deposit tokens under. Delegated depositing is NOT supported.
    /// Depositing DOES NOT mint shares (unlike ERC4626) so the overall vaulted
    /// experience is much simpler as there is always a 1:1 relationship between
    /// deposited assets and vault balances globally and individually. This
    /// mitigates rounding/dust issues, speculative behaviour on derived assets,
    /// possible regulatory issues re: whether a vault share is a security, code
    /// bloat on the vault, complex mint/deposit/withdraw/redeem 4-way logic,
    /// the need for preview functions, etc. etc.
    ///
    /// At the same time, allowing vault IDs to be specified by the depositor
    /// allows much more granular and direct control over token movements within
    /// Raindex than either ERC4626 vault shares or mere contract-level ERC20
    /// allowances can facilitate.
    ///
    /// Vault IDs are namespaced by the token address so there is no risk of
    /// collision between tokens. For example, vault ID 1 for token A is
    /// completely different to vault ID 1 for token B.
    ///
    /// `0` amount deposits are unsupported as underlying token contracts
    /// handle `0` value transfers differently and this would be a source of
    /// confusion. The Raindex MUST revert with `ZeroDepositAmount` if the
    /// amount is zero.
    ///
    /// Vault ID `0` is disallowed for deposits to avoid collision with vaultless
    /// orders. The Raindex MUST revert with `ZeroVaultId` if the vault ID is
    /// zero.
    ///
    /// @param token The token to deposit.
    /// @param vaultId The vault ID to deposit under.
    /// @param depositAmount The amount of tokens to deposit.
    /// @param tasks Additional tasks to run after the deposit. Deposit
    /// information SHOULD be made available during evaluation in context.
    /// If ANY of the post tasks revert, the deposit MUST be reverted.
    function deposit4(address token, bytes32 vaultId, Float depositAmount, TaskV2[] calldata tasks) external;

    /// Allows the sender to withdraw any tokens from their own vaults. If the
    /// withdrawer has an active flash loan debt denominated in the same token
    /// being withdrawn then Raindex will merely reduce the debt and NOT send
    /// the amount of tokens repaid to the flashloan debt.
    ///
    /// MUST revert if the amount _requested_ to withdraw is zero. The withdrawal
    /// MAY still not move any tokens (without revert) if the vault balance is
    /// zero, or the withdrawal is used to repay a flash loan, or due to any
    /// other internal accounting.
    ///
    /// Vault ID `0` is NOT supported due to collision with vaultless orders.
    /// The Raindex MUST revert with `ZeroVaultId` if the vault ID is zero.
    ///
    /// @param token The token to withdraw.
    /// @param vaultId The vault ID to withdraw from.
    /// @param targetAmount The amount of tokens to attempt to withdraw. MAY
    /// result in fewer tokens withdrawn if the vault balance is lower than the
    /// target amount. MAY NOT be zero, the Raindex MUST revert with
    /// `ZeroWithdrawTargetAmount` if the amount is zero.
    /// @param tasks Additional tasks to run after the withdraw. Withdraw
    /// information SHOULD be made available during evaluation in context.
    /// If ANY of the tasks revert, the withdraw MUST be reverted.
    function withdraw4(address token, bytes32 vaultId, Float targetAmount, TaskV2[] calldata tasks) external;

    /// Returns true if the order exists, false otherwise.
    /// @param orderHash The hash of the order to check.
    /// @return exists True if the order exists, false otherwise.
    function orderExists(bytes32 orderHash) external view returns (bool exists);

    /// Quotes the provided order for the caller.
    /// The caller is considered to be the counterparty to the order, for the
    /// purposes of evaluating the quote. However, the caller's vault balances
    /// and/or tokens in wallet are not considered in the quote. This means the
    /// output max can exceed what the caller could actually pay for.
    /// Both the output max and io ratio are returned as rain floating point
    /// values, ignoring any token decimals, so are not the literal amounts that
    /// would be moved in the order were it to clear.
    /// @param quoteConfig The configuration for the quote.
    /// @return exists True if the order exists, false otherwise.
    /// @return outputMax The maximum output amount that the order could send.
    /// Is `0` if the order does not exist.
    /// @return ioRatio The input:output ratio of the order. Is `0` if the order
    /// does not exist.
    function quote2(QuoteV2 calldata quoteConfig) external view returns (bool exists, Float outputMax, Float ioRatio);

    /// Given an order config, deploys the expression and builds the full `Order`
    /// for the config, then records it as an active order. Delegated adding an
    /// order is NOT supported. The `msg.sender` that adds an order is ALWAYS
    /// the owner and all resulting vault movements are their own.
    ///
    /// MUST revert with `OrderNoSources` if the order has no associated
    /// calculation and `OrderNoHandleIO` if the order has no handle IO
    /// entrypoint. The calculation MUST return at least two values from
    /// evaluation, the maximum amount and the IO ratio. The handle IO entrypoint
    /// SHOULD return zero values from evaluation. Either MAY revert during
    /// evaluation on the interpreter, which MUST prevent the order from
    /// clearing.
    ///
    /// MUST revert with `OrderNoInputs` if the order has no inputs.
    /// MUST revert with `OrderNoOutputs` if the order has no outputs.
    ///
    /// If the order already exists, the Raindex MUST NOT change state, which
    /// includes not emitting an event. Instead it MUST return false. If the
    /// Raindex modifies state it MUST emit an `AddOrderV3` event and return
    /// true.
    ///
    /// If vault ID is `0` for any input or output, this indicates a vaultless
    /// order for that token. Vaultless orders draw from or pay to the order's
    /// owner's wallet directly rather than any internal vault.
    ///
    /// @param config All config required to build an `Order`.
    /// @param tasks Additional tasks to run after the order is added.
    /// Order information SHOULD be made available during evaluation in context.
    /// If ANY of the tasks revert, the order MUST NOT be added.
    /// @return stateChanged True if the order was added, false if it already
    /// existed.
    function addOrder4(OrderConfigV4 calldata config, TaskV2[] calldata tasks) external returns (bool stateChanged);

    /// Order owner can remove their own orders. Delegated order removal is NOT
    /// supported and will revert. Removing an order multiple times or removing
    /// an order that never existed are valid; the transaction will complete
    /// with that order hash definitely, redundantly not live.
    ///
    /// If a live order is removed the Raindex MUST change state, emit a
    /// `RemoveOrderV3` event and return true. If the order is not live the
    /// Raindex MUST NOT change state, which includes not emitting an event.
    /// Instead it MUST return false.
    ///
    /// @param order The `Order` data exactly as it was added.
    /// @param tasks Additional tasks to run after the order is removed.
    /// Order information SHOULD be made available during evaluation in context.
    /// If ANY of the tasks revert, the order MUST NOT be removed.
    /// @return stateChanged True if the order was removed, false if it did not
    /// exist.
    function removeOrder3(OrderV4 calldata order, TaskV2[] calldata tasks) external returns (bool stateChanged);

    /// Allows `msg.sender` to attempt to fill a list of orders in sequence
    /// without needing to place their own order and clear them. This works like
    /// a market buy but against a specific set of orders. Every order will
    /// looped over and calculated individually then filled maximally until the
    /// request input/output limit is reached for the `msg.sender`. Whether the
    /// limit applies to input or output is determined by the `IOIsInput` flag
    /// in `TakeOrdersConfigV5`. The `msg.sender` is
    /// responsible for selecting the best orders at the time according to their
    /// criteria and MAY specify a maximum IO ratio to guard against an order
    /// spiking the ratio beyond what the `msg.sender` expected and is
    /// comfortable with. As orders may be removed and calculate their ratios
    /// dynamically, all issues fulfilling an order other than misconfiguration
    /// by the `msg.sender` are no-ops and DO NOT revert the transaction. This
    /// allows the `msg.sender` to optimistically provide a list of orders that
    /// they aren't sure will completely fill at a good price, and fallback to
    /// more reliable orders further down their list. Misconfiguration such as
    /// token mismatches are errors that revert as this is known and static at
    /// all times to the `msg.sender` so MUST be provided correctly. `msg.sender`
    /// MAY specify a minimum input/output that MUST be reached across all
    /// orders in the list, otherwise the transaction will revert, this MAY be
    /// set to zero.
    ///
    /// Exactly like withdraw, if there is an active flash loan for `msg.sender`
    /// they will have their outstanding loan reduced by the final input amount
    /// preferentially before sending any tokens. Notably this allows arb bots
    /// implemented as flash loan borrowers to connect orders against external
    /// liquidity directly by paying back the loan with a `takeOrders` call and
    /// outputting the result of the external trade.
    ///
    /// Rounding errors always favour the order never the `msg.sender`.
    ///
    /// @param config The constraints and list of orders to take, orders are
    /// processed sequentially in order as provided, there is NO ATTEMPT onchain
    /// to predict/filter/sort these orders other than evaluating them as
    /// provided. Inputs and outputs are from the perspective of `msg.sender`
    /// except for values specified by the orders themselves which are the from
    /// the perspective of that order.
    /// @return totalTakerInput Total tokens sent to `msg.sender`, taken from order
    /// vaults processed.
    /// @return totalTakerOutput Total tokens taken from `msg.sender` and distributed
    /// between vaults.
    function takeOrders4(TakeOrdersConfigV5 calldata config)
        external
        returns (Float totalTakerInput, Float totalTakerOutput);

    /// Allows `msg.sender` to match two live orders placed earlier by
    /// non-interactive parties and claim a bounty in the process. The clearer is
    /// free to select any two live orders on the Raindex for matching and as
    /// long as they have compatible tokens, ratios and amounts, the orders will
    /// clear. Clearing the orders DOES NOT remove them from the Raindex, they
    /// remain live until explicitly removed by their owner. Even if the input
    /// vault balances are completely emptied, the orders remain live until
    /// removed. This allows order owners to deploy a strategy over a long period
    /// of time and periodically top up the input vaults. Clearing two orders
    /// from the same owner is disallowed.
    ///
    /// Any mismatch in the ratios between the two orders will cause either more
    /// inputs than there are available outputs (transaction will revert) or less
    /// inputs than there are available outputs. In the latter case the excess
    /// outputs are given to the `msg.sender` of clear, to the vaults they
    /// specify in the clear config. This not only incentivises "automatic" clear
    /// calls for both alice and bob, but incentivises _prioritising greater
    /// ratio differences_ with a larger bounty. The second point is important
    /// because it implicitly prioritises orders that are further from the
    /// current market price, thus putting constant increasing pressure on the
    /// entire system the further it drifts from the norm, no matter how esoteric
    /// the individual order expressions and sizings might be.
    ///
    /// All else equal there are several factors that would impact how reliably
    /// some order clears relative to the wider market, such as:
    ///
    /// - Bounties are effectively percentages of cleared amounts so larger
    ///   orders have larger bounties and cover gas costs more easily
    /// - High gas on the network means that orders are harder to clear
    ///   profitably so the negative spread of the ratios will need to be larger
    /// - Complex and stateful expressions cost more gas to evalulate so the
    ///   negative spread will need to be larger
    /// - Erratic behavior of the order owner could reduce the willingness of
    ///   third parties to interact if it could result in wasted gas due to
    ///   orders suddently being removed before clearance etc.
    /// - Dynamic and highly volatile words used in the expression could be
    ///   ignored or low priority by clearers who want to be sure that they can
    ///   accurately predict the ratios that they include in their clearance
    /// - Geopolitical issues such as sanctions and regulatory restrictions could
    ///   cause issues for certain owners and clearers
    ///
    /// @param alice Some order to clear.
    /// @param bob Another order to clear.
    /// @param clearConfig Additional configuration for the clearance such as
    /// how to handle the bounty payment for the `msg.sender`.
    /// @param aliceSignedContext Optional signed context that is relevant to A.
    /// @param bobSignedContext Optional signed context that is relevant to B.
    function clear3(
        OrderV4 memory alice,
        OrderV4 memory bob,
        ClearConfigV2 calldata clearConfig,
        SignedContextV1[] memory aliceSignedContext,
        SignedContextV1[] memory bobSignedContext
    ) external;
}
