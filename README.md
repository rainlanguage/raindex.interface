# Raindex

Raindex is a programmable, dynamic onchain order book. Orders are not static
limit orders — they are strategies written as Rain interpreter expressions that
evaluate at match time. This means order amounts and ratios can change based on
onchain state, time, oracle prices, or any other logic the expression author
encodes. Two orders clear when their evaluated ratios overlap, with any surplus
going to the clearer as a bounty.

## Raindex vs. traditional order books

Traditional onchain order books (e.g. dYdX, Serum) replicate the familiar
limit-order model: users place fixed-price bids and asks, a matching engine
pairs them, and fills execute at the stated price. This works, but each
repricing requires a new transaction, making active market-making expensive and
slow.

Raindex replaces static prices with executable expressions. An order's ratio and
maximum amount are computed fresh every time someone attempts to match it. The
expression can read any onchain state — block number, oracle feeds, vault
balances, its own persistent storage — so a single order can implement
strategies that would otherwise require off-chain bots continuously cancelling
and reposting.

## Raindex vs. AMMs

AMMs (Uniswap, Curve, Balancer) achieve always-on liquidity by pooling tokens
into a shared reserve governed by a bonding curve. Liquidity providers deposit
tokens and receive pool shares; the curve mechanically sets the price. This
removes the need for active order management but introduces impermanent loss,
pool-level MEV extraction, and limited strategic control for individual LPs.

Raindex keeps individual ownership of tokens in per-user vaults — there is no
shared pool. Each order owner defines their own pricing logic, so there is no
bonding curve imposing a single price on all participants. Because orders
evaluate independently, one user's strategy cannot dilute or override another's.
Clearers (analogous to AMM arbitrageurs) match overlapping orders and keep the
surplus, providing the same "always available" clearing incentive that
arbitrageurs provide to AMMs, but without requiring passive LPs to share a pool.

This repo defines the Solidity interfaces and types for Raindex. It does not
contain the implementation.

## Dev stuff

### Local environment & CI

Uses nixos.

Install `nix develop` - https://nixos.org/download.html.

Run `nix develop` in this repo to drop into the shell. Please ONLY use the nix
version of `foundry` for development, to ensure versions are all compatible.

Read the `flake.nix` file to find some additional commands included for dev and
CI usage.

## Legal stuff

Everything is under DecentraLicense 1.0 (DCL-1.0) which can be found in
`LICENSES/`.

This is basically `CAL-1.0` which is an open source license
https://opensource.org/license/cal-1-0

The non-legal summary of DCL-1.0 is that the source is open, as expected, but
also user data in the systems that this code runs on must also be made available
to those users as relevant, and that private keys remain private.

Roughly it's "not your keys, not your coins" aware, as close as we could get in
legalese.

This is the default situation on permissionless blockchains, so shouldn't
require any additional effort by dev-users to adhere to the license terms.

This repo is REUSE 3.2 compliant https://reuse.software/spec-3.2/ and compatible
with `reuse` tooling (also available in the nix shell here).

```
nix develop -c rainix-sol-legal
```

## Contributions

Contributions are welcome **under the same license** as above.

Contributors agree and warrant that their contributions are compliant.
