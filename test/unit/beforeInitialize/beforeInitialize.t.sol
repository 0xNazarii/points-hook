// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Types
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

// Libraries
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CustomRevert} from "v4-core/libraries/CustomRevert.sol";

// Contracts
import {PointsHook} from "../../../src/PointsHook.sol";
import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";

// Test
import {Base_Test} from "../../Base.t.sol";

contract PointsHook_beforeInitialize is Base_Test {
    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_beforeInitialize_RevertsWhen_PoolInitializedDirectly()
        public
    {
        // Arrange
        PoolKey memory newKey = PoolKey(
            ethCurrency,
            tokenCurrency,
            500,
            10,
            hook
        );

        // Act and Assert: the PoolManager wraps the hook's revert
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
                IHooks.beforeInitialize.selector,
                abi.encodeWithSelector(
                    PointsHook.MustInitializeThroughHook.selector
                ),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        vm.prank(users.alice);
        manager.initialize(newKey, SQRT_PRICE_1_1);
    }

    function test_beforeInitialize_RevertsWhen_CallerIsNotPoolManager()
        public
    {
        // Act and Assert
        vm.expectRevert(ImmutableState.NotPoolManager.selector);
        vm.prank(users.alice);
        hook.beforeInitialize(address(hook), key, SQRT_PRICE_1_1);
    }
}
