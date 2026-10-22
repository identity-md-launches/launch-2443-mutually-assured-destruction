// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Local fixture only. Models CREATE2 and the launch's token transfers, not the Uniswap pool.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (MADToken) {
        return new MADToken{salt: salt}();
    }

    function distribute(MADToken token, address distributor, address pool, address remainder) external {
        uint256 supply = token.totalSupply();
        require(token.transfer(distributor, supply * 1_000 / 10_000));
        require(token.transfer(pool, supply * 8_500 / 10_000));
        require(token.transfer(remainder, supply * 500 / 10_000));
    }
}

contract LaunchCompatibilityTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    TokenFactoryFixture internal factory;
    MADToken internal token;
    address internal distributor = makeAddr("distributor fixture");
    address internal pool = makeAddr("pool fixture");
    address internal remainder = makeAddr("remainder fixture");
    address internal claimant = makeAddr("claimant fixture");
    address internal trader = makeAddr("trader fixture");

    function setUp() public {
        factory = new TokenFactoryFixture();
        token = factory.deploy(keccak256("MAD launch fixture"));
    }

    function test_Create2DeploymentMintsEntireSupplyToFactory() public view {
        bytes32 expectedHash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(factory), keccak256("MAD launch fixture"), keccak256(type(MADToken).creationCode)
            )
        );
        assertEq(address(token), address(uint160(uint256(expectedHash))));
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertGt(address(token).code.length, 0);
        assertLe(address(token).code.length, 24_576);
    }

    function test_LaunchDistributionAndClaimsArriveWhole() public {
        factory.distribute(token, distributor, pool, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), 100_000_000 ether);
        assertEq(token.balanceOf(pool), 850_000_000 ether);
        assertEq(token.balanceOf(remainder), 50_000_000 ether);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, 100_000_000 ether));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), 100_000_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_PoolTokenLegsTransferExactlyInBothDirections(uint256 amount) public {
        factory.distribute(token, distributor, pool, remainder);
        uint256 poolBalance = token.balanceOf(pool);
        amount = bound(amount, 1, poolBalance);
        vm.prank(pool);
        assertTrue(token.transfer(trader, amount));
        assertEq(token.balanceOf(trader), amount);
        assertEq(token.balanceOf(pool), poolBalance - amount);

        vm.prank(trader);
        assertTrue(token.transfer(pool, amount));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), poolBalance);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
