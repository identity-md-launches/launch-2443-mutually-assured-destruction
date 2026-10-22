// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev All recipients are in the actor set, so summing their balances covers the entire supply.
contract MADTokenHandler is Test {
    MADToken public immutable token;
    address[5] public actors;

    constructor() {
        token = new MADToken();
        actors = [address(this), makeAddr("actor one"), makeAddr("actor two"), makeAddr("actor three"), address(token)];
        // Seed active holders so delegated actions exercise positive balances from the start.
        for (uint256 i = 1; i < 4; ++i) {
            token.transfer(actors[i], token.INITIAL_SUPPLY() / 5);
        }
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = actors[toSeed % 5];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        if (from == to) {
            assertEq(token.balanceOf(from), fromBefore);
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 beforeBalance = token.balanceOf(owner);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
        assertEq(token.balanceOf(owner), beforeBalance);
    }

    function delegatedMove(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = actors[toSeed % 5];
        uint256 beforeAllowance = token.allowance(owner, spender);
        uint256 beforeBalance = token.balanceOf(owner);
        uint256 beforeRecipient = token.balanceOf(to);
        uint256 available = beforeAllowance < beforeBalance ? beforeAllowance : beforeBalance;
        amount = bound(amount, 0, available);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(
            token.allowance(owner, spender),
            beforeAllowance == type(uint256).max ? type(uint256).max : beforeAllowance - amount
        );
        if (owner == to) {
            assertEq(token.balanceOf(owner), beforeBalance);
        } else {
            assertEq(token.balanceOf(owner), beforeBalance - amount);
            assertEq(token.balanceOf(to), beforeRecipient + amount);
        }
    }

    function unauthorizedMove(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = actors[toSeed % 5];
        uint256 allowed = token.allowance(owner, spender);
        if (allowed == type(uint256).max) return;
        uint256 beforeOwner = token.balanceOf(owner);
        uint256 beforeRecipient = token.balanceOf(to);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, allowed + 1);
        assertEq(token.allowance(owner, spender), allowed);
        assertEq(token.balanceOf(owner), beforeOwner);
        assertEq(token.balanceOf(to), beforeRecipient);
    }

    function _actor(uint256 seed) private view returns (address) {
        // The token contract can receive funds but cannot originate transfers or approvals.
        return actors[seed % 4];
    }
}

contract MADTokenInvariantTest is Test {
    MADTokenHandler internal handler;
    MADToken internal token;

    function setUp() public {
        handler = new MADTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = MADTokenHandler.move.selector;
        selectors[1] = MADTokenHandler.approve.selector;
        selectors[2] = MADTokenHandler.delegatedMove.selector;
        selectors[3] = MADTokenHandler.unauthorizedMove.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyAndMetadataStayFixed() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.decimals(), 18);
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
    }

    function invariant_AllTokensRemainAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, 1_000_000_000 ether);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
