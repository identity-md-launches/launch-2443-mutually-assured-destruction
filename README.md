# Mutually Assured Destruction (MAD)

A fixed-supply ERC-20 token. The constructor mints **1,000,000,000 MAD with 18 decimals** to its immediate deployer. The entire production implementation is in [`src/MADToken.sol`](src/MADToken.sol), using the vendored OpenZeppelin ERC20 implementation.

## Token behavior and assumptions

| Property | Value |
| --- | --- |
| Solidity contract | `MADToken` |
| Token name | `Mutually Assured Destruction` |
| Symbol | `MAD` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None |
| Initial recipient | `msg.sender` in the constructor |
| Deployment value | `0` ETH |
| Administrative roles | None |

The brief specifies metadata and a constructor mint. The name is treated as branding; it does not imply a destruction, slashing, burn, or retaliation feature. Standard ERC-20 transfers and approvals are the complete transfer policy. There are no token fees, rebases, transfer limits, allowlists, or external service dependencies.

- The constructor is the only reachable mint operation. Supply remains fixed for the lifetime of this deployed contract. No public mint, burn, `burnFrom`, initialization, ownership, pause, blacklist, seizure, or upgrade function exists.
- `transfer` and `transferFrom` deliver exactly the requested amount. They return `true` on success and revert with OpenZeppelin's ERC-6093 custom errors on failure.
- Zero-value transfers between nonzero addresses succeed and emit `Transfer`. Transfers to the zero address and approvals to the zero spender revert. A self-transfer preserves the balance and still requires sufficient balance.
- `approve` replaces an allowance and emits `Approval`; approving zero revokes it. `transferFrom` consumes finite allowances, including self-transfers. A `type(uint256).max` allowance is treated as unlimited and is not reduced. This OpenZeppelin version does not emit `Approval` when spending an allowance; integrations should read `allowance()`.
- Recipients receive no callback. The token neither calls outside contracts nor accepts ordinary ETH payments. Tokens sent to a contract that cannot transfer them, including MADToken itself, cannot be recovered by an administrator.

## Build and check

Run from this repository's root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x438bb5b880a2c072d31a60ed22fab067048eeee46ef03d10392a25e37dac95e5 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer settings (200 runs), and `bytecode_hash = "none"`. It enables neither FFI nor filesystem cheatcode access. The target launch chain is Ethereum (chain ID 1); the token has no chain-specific runtime dependencies. Compiler and EVM settings must stay the same when reproducing bytecode.

All Solidity dependencies are ordinary files under `lib/`; no package installation, submodule, RPC, key, environment configuration, or network download is needed by the tests. The only prerequisite beyond Foundry is the pinned compiler. Dependency versions, archive hashes, and licenses are included:

- OpenZeppelin Contracts **v5.0.2**: the ERC20 implementation and its transitive imports, under the MIT license. See [`lib/openzeppelin-contracts/UPSTREAM.md`](lib/openzeppelin-contracts/UPSTREAM.md).
- forge-std **v1.9.7**: test utilities, under the upstream MIT/Apache-2.0 licenses. See [`lib/forge-std/UPSTREAM.md`](lib/forge-std/UPSTREAM.md).

Tests have isolated setup and do not read or set environment variables. The command above supplies the requested fuzz seed to Foundry itself; configuration does not override the runner's seed. Fuzz tests use 1,024 runs per property. Each stateful invariant uses 256 sequences of up to 64 actions, with unexpected reverts treated as failures.

## Deployment parameters and responsibilities

Deploy `src/MADToken.sol:MADToken` directly from its compiled creation bytecode with **no constructor arguments**, **no initialization call**, and **no ETH**. It is not a proxy and contains no linked libraries. `out/MADToken.sol/MADToken.json` is the generated artifact. No application contracts are needed for this token.

The immediate contract creator receives all `10^27` units. In the planned launch, that creator is the launch factory, not the transaction's origin or the requester wallet. Deploying through an extra helper would instead give the helper all the tokens. The factory must therefore deploy the token and handle the intended distribution. A local CREATE2 fixture tests this recipient behavior.

The launch's distribution and pool settings are handled outside the token by the launch infrastructure:

| Launch setting supplied by the assignment | Value |
| --- | --- |
| Swarm distribution | 10% through the launch's MerkleDistributor |
| Pool allocation | 85% (`poolBps = 8500`) |
| Remainder allocation | 5% to `0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d` |
| Ethereum pair currency | FWA, `0xa0df17b5ac76ababa36e1450e2cbcd18a620c845`, 18 decimals |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Initial market cap in FWA minor units | `2000000000000000000000000` |
| Supplied pool price provenance | `79228162514264337593543950336`; the deployer derives the actual opening price from launch economics |

These values are supplied launch data, not addresses the token calls or parameters its constructor accepts. The token imposes no special exemptions because every transfer is already exact. The later manifest step is responsible for recording this contract, metadata, exact minor-unit supply, empty constructor arguments, and launch economics. This repository does not supply a launch manifest or broadcast transactions.

### After launch

There are no owner-settable settings, services to configure, admin keys, maintenance calls, or ownership transfers. The launch operator is responsible for verifying the deployed source with the pinned build settings and confirming the metadata, initial supply, and factory distribution. The factory and distribution infrastructure handle the pool and contributor claims.

Holders control their transfers and spender approvals. Spenders can use the allowances granted to them; holders should approve only the amounts they intend to authorize and revoke approvals they no longer need. As with standard ERC-20, replacing a live allowance may race with its spender: applications should revoke it and confirm that transaction before setting a replacement when this matters. There is no recovery authority for mistaken transfers or lost wallet access.

## Validation and security scope

- `test/MADToken.t.sol`: metadata, sole constructor mint and event, exact transfers, approvals and revocation, finite/infinite allowances, smallest-unit/zero/self/maximum-value cases, rejection of unauthorized or excessive spending, failure rollback, absent privileged entrypoints, and fuzzed success/failure properties.
- `test/LaunchCompatibility.t.sol`: factory CREATE2 deployment, full factory allocation, exact 10%/85%/5% forwarding, distributor claims, and token transfers in both directions between a pool fixture and a trader.
- `test/MADToken.invariant.t.sol`: randomized transfers, approvals, authorized delegated transfers, and rejected unauthorized attempts across several holders; checks fixed metadata/supply and conservation of every minted unit, including tokens received by the token contract.

The supplied security reference was used to review access control, arithmetic, input validation, events, external interactions, and privileged code paths. The deployed token makes no external calls and has no hooks, signatures, oracle, valuable randomness, upgrade machinery, or public supply-changing path. Solidity's checked arithmetic and OpenZeppelin's balance/allowance checks apply.

The local launch fixture exercises the token legs, not actual Uniswap pool initialization, liquidity math, or swaps. The protected launch integration suite depends on the later manifest and launch infrastructure and belongs to downstream verification. Local Foundry tests are not an independent security audit. Independent adversarial review and final launch verification remain the release process's responsibilities; Slither and Mythril are not part of this project's local checks.

Local validation completed with the commands above: `forge build`, seeded `forge test`, and `forge fmt --check` all passed. Foundry reported 33 passing tests, including five fuzz properties (5,120 generated cases) and the combined invariant suite (16,384 handler calls, zero unexpected reverts). The compiled token has 2,657 bytes of creation code and 1,752 bytes of runtime code, no link references, and no executable `DELEGATECALL`, `CALLCODE`, or `SELFDESTRUCT` under the protected suite's opcode scan. Its ABI contains only the no-argument constructor, standard ERC-20 functions/events/errors, and the `INITIAL_SUPPLY` getter.
