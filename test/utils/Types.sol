// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev A list of users to be used in tests
struct Users {
    /// @dev Swapper that earns points
    address payable alice;
    /// @dev Second swapper
    address payable bob;
}
