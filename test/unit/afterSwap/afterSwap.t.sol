// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Types
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

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

    /*//////////////////////////////////////////////////////////////
                            CAMPAIGN WINDOW
    //////////////////////////////////////////////////////////////*/

    function test_afterSwap_NoPointsWhen_CampaignNotStarted() public {
        // Arrange
        useFutureCampaignPool();

        // Act
        vm.warp(campaignStart - 1);
        swapEthForToken(users.alice, abi.encode(users.alice));

        // Assert
        assertEq(pointsOf(users.alice), 0, "Alice should get no points");
    }

    function test_afterSwap_MintsPointsWhen_CampaignStarts() public {
        // Arrange
        useFutureCampaignPool();

        // Act
        vm.warp(campaignStart);
        swapEthForToken(users.alice, abi.encode(users.alice));

        // Assert
        assertEq(pointsOf(users.alice), SWAP_POINTS, "Alice should get points");
    }

    function test_afterSwap_MintsPointsWhen_LastSecondOfCampaign() public {
        // Act
        vm.warp(campaignEnd - 1);
        swapEthForToken(users.alice, abi.encode(users.alice));

        // Assert
        assertEq(pointsOf(users.alice), SWAP_POINTS, "Alice should get points");
    }

    function test_afterSwap_NoPointsWhen_CampaignEnded() public {
        // Act
        vm.warp(campaignEnd);
        swapEthForToken(users.alice, abi.encode(users.alice));

        // Assert
        assertEq(pointsOf(users.alice), 0, "Alice should get no points");
    }

    function test_afterSwap_SwapSucceedsWhen_OutsideCampaign() public {
        // Arrange
        uint256 tokenBefore = token.balanceOf(users.alice);

        // Act
        vm.warp(campaignEnd);
        swapEthForToken(users.alice, abi.encode(users.alice));

        // Assert
        assertGt(
            token.balanceOf(users.alice),
            tokenBefore,
            "Alice should still receive TOKEN"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Switch to a new pool whose campaign starts in 1 day
    function useFutureCampaignPool() internal {
        campaignStart = uint64(block.timestamp + 1 days);
        campaignEnd = campaignStart + CAMPAIGN_DURATION;

        key = PoolKey(ethCurrency, tokenCurrency, 500, 10, hook);
        hook.initializePool(key, SQRT_PRICE_1_1, campaignStart, campaignEnd);
        addLiquidity(key, 0.1 ether);
        poolIdUint = uint256(PoolId.unwrap(key.toId()));
    }
}
