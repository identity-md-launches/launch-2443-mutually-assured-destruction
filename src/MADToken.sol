// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mutually Assured Destruction
/// @notice A fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract MADToken is ERC20 {
    /// @notice One billion MAD, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev The immediate deployer receives the entire supply. During the launch this is the factory.
    constructor() ERC20("Mutually Assured Destruction", "MAD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
