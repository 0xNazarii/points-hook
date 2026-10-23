// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Types
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

// Libraries
import {Pool} from "v4-core/libraries/Pool.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

// Contracts
import {PointsHook} from "../../../src/PointsHook.sol";

// Test
import {Base_Test} from "../../Base.t.sol";

contract PointsHook_initializePool is Base_Test {
    using StateLibrary for IPoolManager;

    /// @dev A second ETH/TOKEN pool with this hook, not initialized in setUp
    PoolKey internal newKey;

    function setUp() public override {
        super.setUp();
        newKey = PoolKey(ethCurrency, tokenCurrency, 500, 10, hook);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initializePool_StoresCampaignAndInitializesPool() public {
        // Arrange
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 end = start + 7 days;

        // Act
        vm.prank(users.alice);
        int24 tick = hook.initializePool(newKey, SQRT_PRICE_1_1, start, end);

        // Assert
        (uint64 storedStart, uint64 storedEnd) = hook.campaigns(newKey.toId());
        assertEq(storedStart, start, "Campaign start should be stored");
        assertEq(storedEnd, end, "Campaign end should be stored");

        (uint160 sqrtPriceX96, , , ) = manager.getSlot0(newKey.toId());
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1, "Pool should be initialized");
        assertEq(tick, 0, "Tick at price 1 should be 0");
    }

    function test_initializePool_RevertsWhen_HookIsNotThisHook() public {
        // Arrange
        newKey.hooks = IHooks(address(0));

        // Act and Assert
        vm.expectRevert(PointsHook.InvalidHookAddress.selector);
        hook.initializePool(newKey, SQRT_PRICE_1_1, 1, 2);
    }

    function test_initializePool_RevertsWhen_StartEqualsEnd() public {
        // Act and Assert
        vm.expectRevert(PointsHook.InvalidCampaign.selector);
        hook.initializePool(newKey, SQRT_PRICE_1_1, 100, 100);
    }

    function test_initializePool_RevertsWhen_StartAfterEnd() public {
        // Act and Assert
        vm.expectRevert(PointsHook.InvalidCampaign.selector);
        hook.initializePool(newKey, SQRT_PRICE_1_1, 200, 100);
    }

    function test_initializePool_RevertsWhen_PoolAlreadyInitialized() public {
        // Act and Assert: re-initializing can't overwrite the campaign
        vm.expectRevert(Pool.PoolAlreadyInitialized.selector);
        hook.initializePool(key, SQRT_PRICE_1_1, 1, type(uint64).max);

        (uint64 storedStart, uint64 storedEnd) = hook.campaigns(key.toId());
        assertEq(storedStart, campaignStart, "Campaign start should not change");
        assertEq(storedEnd, campaignEnd, "Campaign end should not change");
    }
}
