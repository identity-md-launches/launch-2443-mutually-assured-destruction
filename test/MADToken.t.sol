// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

contract RejectingRecipient {
    fallback() external {
        revert("no callbacks accepted");
    }
}

contract MADTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    MADToken internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new MADToken();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_ConstructorMintsOnceToImmediateDeployerAndEmitsTransfer() public {
        vm.recordLogs();
        vm.prank(alice, bob);
        MADToken deployed = new MADToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_TransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupplyAndOneSmallestUnit() public {
        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToContractDoesNotInvokeRecipient() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function test_RevertTransferToZeroAddressIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertTransferMaxUintWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApproveEmitsEventAndDoesNotMoveFunds() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApproveReplacesAndRevokesAllowance() public {
        token.approve(spender, 100 ether);
        token.approve(spender, 40 ether);
        assertEq(token.allowance(address(this), spender), 40 ether);
        token.approve(spender, 0);
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_AllowancesAreIsolatedByOwnerAndSpender() public {
        token.approve(spender, 100);
        token.approve(bob, 50);
        vm.prank(alice);
        token.approve(spender, 25);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.allowance(address(this), bob), 50);
        assertEq(token.allowance(alice, spender), 25);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_RevertApproveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromDeliversExactAmountAndConsumesAllowance() public {
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));
        assertEq(token.allowance(address(this), spender), 60 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 60 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(bob), 60 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalIsNotConsumed() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_TransferFromToSelfConsumesFiniteAllowanceWithoutMovingBalance() public {
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 40));
        assertEq(token.allowance(address(this), spender), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromWithoutAllowanceSucceeds() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertTransferFromWithoutAllowanceIncludingDeployer() public {
        token.transfer(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertTransferFromAboveAllowanceLeavesStateUnchanged() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 11);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertTransferFromAboveBalanceRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100));
        vm.prank(spender);
        token.transferFrom(alice, bob, 100);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertTransferFromToZeroRestoresAllowance() public {
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertTransferFromZeroCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_NoMintBurnOwnershipPauseSeizureOrUpgradeEntrypoints() public {
        token.transfer(alice, 100 ether);
        bytes[16] memory attempts = [
            abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether),
            abi.encodeWithSignature("mint(uint256)", 1 ether),
            abi.encodeWithSignature("mint()"),
            abi.encodeWithSignature("burn(uint256)", 1 ether),
            abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", alice),
            abi.encodeWithSignature("freeze(address)", alice),
            abi.encodeWithSignature("seize(address)", alice),
            abi.encodeWithSignature("transferOwnership(address)", bob),
            abi.encodeWithSignature("owner()"),
            abi.encodeWithSignature("initialize(address)", bob),
            abi.encodeWithSignature("upgradeTo(address)", bob),
            abi.encodeWithSignature("setMinter(address)", bob),
            abi.encodeWithSignature("setTransfersEnabled(bool)", false),
            abi.encodeWithSignature("setBlacklist(address,bool)", alice, true)
        ];
        for (uint256 i; i < attempts.length; ++i) {
            (bool deployerSuccess,) = address(token).call(attempts[i]);
            assertFalse(deployerSuccess);
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(attempts[i]);
            assertFalse(strangerSuccess);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_RejectsNativeCurrency() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
    }

    function testFuzz_TransferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_TransferFromRespectsBalanceAndAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertTransferAboveBalance(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        token.transfer(alice, balance);
        uint256 amount = balance + excess;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertTransferAboveAllowance(uint256 approved, uint256 excess) public {
        approved = bound(approved, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - approved);
        uint256 amount = approved + excess;
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
