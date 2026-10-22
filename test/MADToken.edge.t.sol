// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

contract MADTokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    MADToken internal token;
    address internal alice = makeAddr("edge alice");
    address internal spender = makeAddr("edge spender");

    function setUp() public {
        token = new MADToken();
    }

    function test_SupplyIsExactlyTenToTheTwentySeven() public view {
        assertEq(SUPPLY, 10 ** 27);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    function test_RuntimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 2);
        // solc appends a CBOR metadata trailer whose length is the last two bytes; it is data, not code.
        uint256 trailer = (uint256(uint8(code[code.length - 2])) << 8) | uint8(code[code.length - 1]);
        assertLt(trailer + 2, code.length);
        uint256 end = code.length - trailer - 2;
        for (uint256 i; i < end; ++i) {
            uint8 op = uint8(code[i]);
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
            if (op >= 0x60 && op <= 0x7f) i += op - 0x5f;
        }
    }

    function test_EachDeploymentIsIndependent() public {
        vm.prank(alice);
        MADToken second = new MADToken();
        assertTrue(token.transfer(spender, 5));
        assertEq(second.balanceOf(spender), 0);
        assertEq(second.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply() + second.totalSupply(), 2 * SUPPLY);
    }

    function test_TransferFromDoesNotEmitApproval() public {
        token.approve(spender, 10);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(token.allowance(address(this), spender), 6);
    }

    function test_AllowanceOneBelowMaxIsConsumed() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
    }

    function test_SelfApprovalStillRequiredForOwnTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_RevertSecondSpendOfExhaustedAllowance() public {
        token.approve(spender, 7);
        vm.startPrank(spender);
        token.transferFrom(address(this), alice, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 7);
    }

    function test_RevertSpendingAboveBalanceDespiteInfiniteAllowance() public {
        token.transfer(alice, 3);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 3, 4));
        vm.prank(spender);
        token.transferFrom(alice, address(this), 4);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    function test_RevertUnknownSelectorAndCalldata() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        (ok,) = address(token).call(hex"00");
        assertFalse(ok);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TokensSentToTokenContractAreStuck() public {
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        // No function lets anyone move the token contract's own balance.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(token), address(this), 1);
        assertEq(token.balanceOf(address(token)), 1 ether);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ConstructorMintsWholeSupplyToAnyDeployer(address deployer) public {
        vm.assume(deployer != address(0));
        vm.prank(deployer);
        MADToken deployed = new MADToken();
        assertEq(deployed.balanceOf(deployer), SUPPLY);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferToAnyNonzeroRecipientIsExact(address to, uint256 amount) public {
        to = to == address(0) ? alice : to;
        amount = bound(amount, 0, SUPPLY);
        uint256 toBefore = token.balanceOf(to);
        assertTrue(token.transfer(to, amount));
        if (to == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), toBefore + amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ApproveStoresAnyValueVerbatim(address who, uint256 first, uint256 second) public {
        who = who == address(0) ? spender : who;
        token.approve(who, first);
        assertEq(token.allowance(address(this), who), first);
        token.approve(who, second);
        assertEq(token.allowance(address(this), who), second);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_SplitSpendEqualsSingleSpend(uint256 approved, uint256 a, uint256 b) public {
        approved = bound(approved, 0, SUPPLY);
        a = bound(a, 0, approved);
        b = bound(b, 0, approved - a);
        token.approve(spender, approved);
        vm.startPrank(spender);
        token.transferFrom(address(this), alice, a);
        token.transferFrom(address(this), alice, b);
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), approved - a - b);
        assertEq(token.balanceOf(alice), a + b);
        assertEq(token.balanceOf(address(this)), SUPPLY - a - b);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RevertTransferFromAnyCallerWithoutAllowance(address caller, uint256 amount) public {
        vm.assume(caller != address(0));
        amount = bound(amount, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, caller, 0, amount));
        vm.prank(caller);
        token.transferFrom(address(this), caller, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }
}
