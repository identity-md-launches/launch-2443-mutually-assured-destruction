// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Model-based handler: every call, successful or not, is checked against an independent ledger.
/// Inputs are deliberately allowed to exceed balances and allowances and to target the zero address, so
/// failure paths run inside random sequences and must leave every balance and allowance untouched.
contract MADLedgerHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant ACTORS = 5;

    MADToken public immutable token;
    address[ACTORS] public actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostSucceeded;
    uint256 public ghostRejected;
    uint256 public ghostMoved;

    constructor() {
        token = new MADToken();
        actors = [address(this), makeAddr("ledger a"), makeAddr("ledger b"), makeAddr("ledger c"), address(token)];
        ghostBalance[address(this)] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount, bool toZero) external {
        address from = _sender(fromSeed);
        address to = toZero ? address(0) : _recipient(toSeed);
        amount = _amount(amount, ghostBalance[from]);

        bytes memory expectedError;
        if (to == address(0)) {
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else if (amount > ghostBalance[from]) {
            expectedError = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, ghostBalance[from], amount
            );
        }

        vm.prank(from);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        _checkOutcome(ok, ret, expectedError);
        if (ok) _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 mode) external {
        address owner = _sender(ownerSeed);
        address spender = mode % 8 == 0 ? address(0) : _recipient(spenderSeed);
        // Mix exact edge values with arbitrary ones.
        if (mode % 5 == 1) amount = type(uint256).max;
        else if (mode % 5 == 2) amount = 0;
        else if (mode % 5 == 3) amount = bound(amount, 0, SUPPLY);

        bytes memory expectedError;
        if (spender == address(0)) {
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        }

        vm.prank(owner);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.approve, (spender, amount)));
        _checkOutcome(ok, ret, expectedError);
        if (ok) ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amount, bool toZero)
        external
    {
        address spender = _sender(spenderSeed);
        address owner = _recipient(ownerSeed);
        address to = toZero ? address(0) : _recipient(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 balance = ghostBalance[owner];
        amount = _amount(amount, allowed < balance ? allowed : balance);

        // OpenZeppelin checks the allowance before the balance and the receiver.
        bytes memory expectedError;
        if (amount > allowed) {
            expectedError =
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount);
        } else if (to == address(0)) {
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else if (amount > balance) {
            expectedError =
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
        }

        vm.prank(spender);
        (bool ok, bytes memory ret) = address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        _checkOutcome(ok, ret, expectedError);
        if (ok) {
            if (allowed != type(uint256).max) ghostAllowance[owner][spender] = allowed - amount;
            _move(owner, to, amount);
        }
    }

    function _checkOutcome(bool ok, bytes memory ret, bytes memory expectedError) private {
        if (expectedError.length == 0) {
            assertTrue(ok, "model expected success");
            assertTrue(abi.decode(ret, (bool)), "success must return true");
            ++ghostSucceeded;
        } else {
            assertFalse(ok, "model expected a revert");
            assertEq(ret, expectedError, "wrong revert reason");
            ++ghostRejected;
        }
    }

    function _move(address from, address to, uint256 amount) private {
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostMoved += amount;
    }

    /// @dev Usually a valid amount, sometimes exactly the limit, sometimes just above it, sometimes anything.
    function _amount(uint256 raw, uint256 limit) private pure returns (uint256) {
        uint256 mode = raw % 4;
        if (mode == 0) return limit;
        if (mode == 1) return limit == type(uint256).max ? limit : limit + 1;
        if (mode == 2) return raw;
        return limit == 0 ? 0 : raw % (limit + 1);
    }

    /// @dev The token contract can hold funds but never originates a call.
    function _sender(uint256 seed) private view returns (address) {
        return actors[seed % (ACTORS - 1)];
    }

    function _recipient(uint256 seed) private view returns (address) {
        return actors[seed % ACTORS];
    }
}

contract MADLedgerInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    MADLedgerHandler internal handler;
    MADToken internal token;

    function setUp() public {
        handler = new MADLedgerHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = MADLedgerHandler.transfer.selector;
        selectors[1] = MADLedgerHandler.approve.selector;
        selectors[2] = MADLedgerHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_BalancesMatchLedger() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.ghostBalance(actor));
            sum += token.balanceOf(actor);
        }
        assertEq(sum, SUPPLY, "units created or destroyed");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_AllowancesMatchLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 5; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.ghostAllowance(owner, spender));
            }
            assertEq(token.allowance(owner, address(0)), 0, "zero spender never approved");
        }
        // The token contract never acts, so nothing it owns can ever be authorised away.
        for (uint256 j; j < 5; ++j) {
            assertEq(token.allowance(address(token), handler.actors(j)), 0);
        }
    }
}
