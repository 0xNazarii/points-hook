// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Test
import {Base_Test} from "../../Base.t.sol";

/// @dev Bad hookData must never revert the swap, it just earns no points
contract PointsHook_assignPoints is Base_Test {
    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_assignPoints_MintsToEncodedAddress() public {
        // Act
        swapEthForToken(users.alice, abi.encode(users.alice));

        // Assert
        assertEq(pointsOf(users.alice), SWAP_POINTS, "Alice should get points");
    }

    function test_assignPoints_MintsToEncodedAddressNotSwapper() public {
        // Act
        swapEthForToken(users.alice, abi.encode(users.bob));

        // Assert
        assertEq(pointsOf(users.bob), SWAP_POINTS, "Bob should get points");
        assertEq(pointsOf(users.alice), 0, "Alice should get no points");
    }

    function test_assignPoints_NoPointsWhen_HookDataEmpty() public {
        // Act
        swapEthForToken(users.alice, "");

        // Assert
        assertEq(pointsOf(users.alice), 0, "Alice should get no points");
    }

    function test_assignPoints_NoPointsWhen_HookDataTooShort() public {
        // Arrange: 20 bytes instead of 32
        bytes memory hookData = abi.encodePacked(users.alice);

        // Act
        swapEthForToken(users.alice, hookData);

        // Assert
        assertEq(pointsOf(users.alice), 0, "Alice should get no points");
    }

    function test_assignPoints_NoPointsWhen_HookDataHasTrailingBytes() public {
        // Arrange: 64 bytes, first word is a valid address
        bytes memory hookData = abi.encode(users.alice, uint256(1));

        // Act
        swapEthForToken(users.alice, hookData);

        // Assert
        assertEq(pointsOf(users.alice), 0, "Alice should get no points");
    }

    function test_assignPoints_NoPointsWhen_UpperBitsNotZero() public {
        // Arrange: lower 20 bytes are Alice, upper 12 bytes are not zero
        uint256 word = (uint256(1) << 160) |
            uint256(uint160(address(users.alice)));

        // Act
        swapEthForToken(users.alice, abi.encode(word));

        // Assert
        assertEq(pointsOf(users.alice), 0, "Alice should get no points");
    }

    function test_assignPoints_NoPointsWhen_ZeroAddress() public {
        // Act
        swapEthForToken(users.alice, abi.encode(address(0)));

        // Assert
        assertEq(pointsOf(address(0)), 0, "Zero address should get no points");
    }

    /*//////////////////////////////////////////////////////////////
                               FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_assignPoints_NoPointsWhen_WrongLength(
        bytes calldata hookData
    ) public {
        // Arrange: a random 32-byte word can be a valid address, covered above
        vm.assume(hookData.length != 32);

        // Act
        swapEthForToken(users.alice, hookData);

        // Assert
        assertEq(pointsOf(users.alice), 0, "Alice should get no points");
    }

    function testFuzz_assignPoints_NoPointsWhen_UpperBitsNotZero(
        uint96 upperBits,
        address user
    ) public {
        // Arrange
        vm.assume(upperBits != 0);
        uint256 word = (uint256(upperBits) << 160) | uint256(uint160(user));

        // Act
        swapEthForToken(users.alice, abi.encode(word));

        // Assert
        assertEq(pointsOf(user), 0, "User should get no points");
    }
}
