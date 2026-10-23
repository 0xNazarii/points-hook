// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Dependencies
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

// Types
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

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

    function test_afterSwap_MintsPointsOnActualEthSpent_ExactOutput()
        public
    {
        // Arrange: ask for a fixed amount of TOKEN out, overpaying ETH
        uint256 ethSentToRouter = 0.01 ether;
        uint256 managerEthBefore = address(manager).balance;

        // Act
        swap(
            key,
            true,
            int256(SWAP_AMOUNT), // Exact output: SWAP_AMOUNT of TOKEN
            ethSentToRouter,
            abi.encode(users.alice)
        );

        // Assert: points follow the ETH the pool actually took
        uint256 ethSpent = address(manager).balance - managerEthBefore;
        assertGt(ethSpent, 0, "Some ETH should be spent");
        assertLt(ethSpent, ethSentToRouter, "Less ETH than sent should be spent");
        assertEq(
            pointsOf(users.alice),
            ethSpent / 5,
            "Alice should get 20% of the ETH actually spent"
        );
    }

    function test_afterSwap_AccumulatesPointsAcrossSwaps() public {
        // Act
        swapEthForToken(users.alice, abi.encode(users.alice));
        swapEthForToken(users.alice, abi.encode(users.alice));

        // Assert
        assertEq(
            pointsOf(users.alice),
            2 * SWAP_POINTS,
            "Alice should get points for both swaps"
        );
    }

    function test_afterSwap_MintsPointsPerPool() public {
        // Arrange: a second ETH/TOKEN pool with its own points id
        PoolKey memory otherKey = PoolKey(
            ethCurrency,
            tokenCurrency,
            500,
            10,
            hook
        );
        hook.initializePool(otherKey, SQRT_PRICE_1_1, campaignStart, campaignEnd);
        addLiquidity(otherKey, 0.1 ether);
        uint256 otherPoolIdUint = uint256(PoolId.unwrap(otherKey.toId()));

        // Act
        swapEthForToken(users.alice, abi.encode(users.alice));
        swap(
            otherKey,
            true,
            -int256(SWAP_AMOUNT),
            SWAP_AMOUNT,
            abi.encode(users.alice)
        );
        swap(
            otherKey,
            true,
            -int256(SWAP_AMOUNT),
            SWAP_AMOUNT,
            abi.encode(users.alice)
        );

        // Assert
        assertEq(
            pointsOf(users.alice),
            SWAP_POINTS,
            "Alice should get one swap of points in the default pool"
        );
        assertEq(
            hook.balanceOf(users.alice, otherPoolIdUint),
            2 * SWAP_POINTS,
            "Alice should get two swaps of points in the other pool"
        );
    }

    function test_afterSwap_NoPointsWhen_SellingTokenForEth() public {
        // Act
        swap(
            key,
            false,
            -int256(SWAP_AMOUNT), // Exact input: SWAP_AMOUNT of TOKEN
            0,
            abi.encode(users.alice)
        );

        // Assert
        assertEq(pointsOf(users.alice), 0, "Alice should get no points");
    }

    function test_afterSwap_NoPointsWhen_PoolIsNotEthPair() public {
        // Arrange: a TOKEN/TOKEN pool with this hook
        (Currency tokenA, Currency tokenB) = deployMintAndApprove2Currencies();
        PoolKey memory tokenKey = PoolKey(tokenA, tokenB, 3000, 60, hook);
        hook.initializePool(tokenKey, SQRT_PRICE_1_1, campaignStart, campaignEnd);
        modifyLiquidityRouter.modifyLiquidity(
            tokenKey,
            LIQUIDITY_PARAMS,
            ZERO_BYTES
        );

        // Act
        swap(tokenKey, true, -int256(SWAP_AMOUNT), 0, abi.encode(users.alice));

        // Assert
        assertEq(
            hook.balanceOf(users.alice, uint256(PoolId.unwrap(tokenKey.toId()))),
            0,
            "Alice should get no points"
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

    /// @dev Swap from this contract in any direction, sending `value` ETH
    function swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 value,
        bytes memory hookData
    ) internal {
        swapRouter.swap{value: value}(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne
                    ? MIN_PRICE_LIMIT
                    : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );
    }

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
