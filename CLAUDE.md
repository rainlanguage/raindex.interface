# CLAUDE.md

## Project Overview

Solidity interface library for Raindex (Rain Protocol's onchain order book).
Defines interfaces and types for an order book where orders are strategies
expressed as Rainlang interpreter bytecode. Part of the Rain Protocol ecosystem.

License: DecentraLicense 1.0 (DCL-1.0). REUSE 3.2 compliant — all files need
SPDX headers:

```solidity
// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
```

## Build & Development

Requires the Nix package manager. **Only use the nix version of Foundry**, not a
system-installed one.

```bash
nix develop                    # Enter dev shell
rainix-sol-prelude             # Setup (run before first build/test)
rainix-sol-test                # Run all tests
rainix-sol-static              # Static analysis (Slither)
rainix-sol-legal               # License/REUSE compliance check
```

Compiler: Solidity 0.8.25, EVM target: cancun, optimizer enabled (1M runs). Fuzz
tests run 2048 iterations.

## Architecture

### Interfaces (`src/interface/`)

- **IRaindexV7** — Current stable interface. Vault-based order book with
  deposit/withdraw, add/remove orders, take orders (market buy), and clear
  (match two orders with bounty). IERC3156 flash loan compliant. Supports
  vaultless orders (vault ID `0` means tokens move directly from wallet) and
  input/output-based take order limits via `IOIsInput` flag.
- **IRaindexV7OrderTaker / IRaindexV7ArbOrderTaker** — Callback interfaces for
  takers receiving tokens during `takeOrders`.
- **ierc3156/** — Flash loan interfaces (IERC3156FlashLender,
  IERC3156FlashBorrower).
- **deprecated/** (v1-v6) — Old interface versions. Do not modify unless
  undeprecating.

### Interface Lifecycle

Stable interfaces live directly in `src/interface/`. New unstable interfaces go
in `src/interface/unstable/` until stabilised. When stabilising, move from
`unstable/` to `src/interface/` and move the previous stable version to
`deprecated/v<N>/`.

### Key Types

All amounts and ratios are Rain floating point (`Float` from `rain.math.float`).
Converted to absolute token values via `decimals()` only when tokens actually
move.

- `OrderV4` — Deployed order: owner, evaluable (interpreter + store + bytecode),
  valid inputs/outputs, nonce
- `OrderConfigV4` — Config for adding an order, includes meta and secret
- `IOV2` — Input/output config: token address + vault ID
- `TaskV2` — Evaluable + signed context, for post-operation callbacks
- `TakeOrdersConfigV4` / `TakeOrdersConfigV5` — Config for batch taking orders
- `ClearConfigV2` / `ClearStateChangeV2` — Config and result for clearing two
  matched orders

### Dependencies

Soldeer packages, declared in `[dependencies]` in `foundry.toml` and locked in
`soldeer.lock` (run `forge soldeer update` after changing them). Import paths
carry the package version (e.g. `rainlang-interface-0.2.3/src/...`). Direct
deps: `rainlang-interface` (Rainlang interpreter interfaces and caller libs) and
`rain-math-float` (Float). Soldeer resolution is flat, so `[dependencies]` also
declares everything `rainlang-interface`'s own src imports
(`@openzeppelin-contracts`, `rain-lib-hash`, `rain-math-binary`,
`rain-sol-codegen`, `rain-solmem`).

## Conventions

- All reverts use custom errors — no `revert("string")` or `require()` with
  string messages.
- Interfaces use `pragma solidity ^0.8.18` (note: differs from interpreter
  interface which uses `^0.8.25`).
- Versioned naming: interfaces (`IRaindexV7`), structs (`OrderV4`,
  `ClearConfigV2`), events (`AddOrderV3`), functions (`deposit4`, `withdraw4`).
- Use `//forge-lint: disable-next-line(...)` comments for lint suppressions:
  `unused-import`, `mixed-case-variable`, `pascal-case-struct`.
- Branch naming: `YYYY-MM-DD-description`.

## Slither Config

Excluded detectors: `assembly-usage`, `solc-version`, `unused-imports`,
`pragma`. Filtered paths: `forge-std`, `openzeppelin`, `rain.math.float`.
