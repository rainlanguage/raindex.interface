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
- **deprecated/** (v1-v6) — Old interface versions. Only import paths may change
  (relocation, dependency bumps); declarations are frozen unless undeprecating.

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
- `TaskV3` — Evaluable + `SignedContextV2`, for post-operation callbacks
- `TakeOrdersConfigV6` / `TakeOrderConfigV5` — Config for batch taking orders
- `ClearConfigV2` / `ClearStateChangeV2` — Config and result for clearing two
  matched orders

### Dependencies

Soldeer packages, declared in `[dependencies]` in `foundry.toml` and locked in
`soldeer.lock` (run `forge soldeer update` after changing them). Import paths
carry the package version (e.g. `rainlang-0.2.27/src/...`). Direct deps:
`rainlang` (Rainlang interpreter interfaces and caller libs, under
`src/interface/` and `src/lib/caller/`) and `rain-math-float` (Float).

## Conventions

- All reverts use custom errors — no `revert("string")` or `require()` with
  string messages.
- Interfaces use `pragma solidity ^0.8.18` (note: differs from interpreter
  interface which uses `^0.8.25`).
- Versioned naming: interfaces (`IRaindexV7`), structs (`OrderV4`,
  `ClearConfigV2`), events (`AddOrderV3`), functions (`deposit5`, `withdraw5`).
- Use `//forge-lint: disable-next-line(...)` comments for lint suppressions:
  `unused-import`, `mixed-case-variable`, `pascal-case-struct`.
- Branch naming: `YYYY-MM-DD-description`.

## Slither Config

Excluded detectors: `assembly-usage`, `solc-version`, `unused-imports`,
`pragma`. Filtered paths: `forge-std`, `openzeppelin`, `rain.math.float`.
