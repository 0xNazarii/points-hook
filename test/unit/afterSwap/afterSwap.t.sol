// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Test
import {Base_Test} from "../../Base.t.sol";

contract PointsHook_afterSwap is Base_Test {
    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_afterSwap_MintsTwentyPercentOfEthSpent() public {
        // Act
        swapEthForToken(users.alice, abi.encode(users.alice));

        // Assert
        assertEq(
            pointsOf(users.alice),
            SWAP_POINTS,
            "Alice should get 20% of the ETH spent as points"
        );
    }
}
