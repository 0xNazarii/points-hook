// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

contract PointsHook is BaseHook, ERC1155 {
    // Time window during which swaps in a pool earn points
    struct Campaign {
        uint64 start;
        uint64 end;
    }

    mapping(PoolId => Campaign) public campaigns;

    error InvalidHookAddress();
    error InvalidCampaign();
    error MustInitializeThroughHook();

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    // Initialize a pool with its points campaign window.
    // Initialize carries no hookData, so the window is stored here before initializing.
    function initializePool(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        uint64 start,
        uint64 end
    ) external returns (int24 tick) {
        if (key.hooks != IHooks(address(this))) revert InvalidHookAddress();
        if (start >= end) revert InvalidCampaign();

        campaigns[key.toId()] = Campaign(start, end);
        tick = poolManager.initialize(key, sqrtPriceX96);
    }

    function _beforeInitialize(
        address sender,
        PoolKey calldata,
        uint160
    ) internal view override returns (bytes4) {
        // Pools must be created via initializePool so they get a campaign window
        if (sender != address(this)) revert MustInitializeThroughHook();
        return this.beforeInitialize.selector;
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // If this is not an ETH-TOKEN pool with this hook attached, ignore
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);

        // We only mint points if user is buying TOKEN with ETH
        if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);

        // No points outside this pool's campaign window
        // Validators can only nudge the timestamp by seconds, fine for a campaign window
        Campaign memory campaign = campaigns[key.toId()];
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < campaign.start || block.timestamp >= campaign.end) {
            return (this.afterSwap.selector, 0);
        }

        // Mint points equal to 20% of the amount of ETH they spent
        // Since its a zeroForOne swap:
        // if amountSpecified < 0:
        //      this is an "exact input for output" swap
        //      amount of ETH they spent is equal to |amountSpecified|
        // if amountSpecified > 0:
        //      this is an "exact output for input" swap
        //      amount of ETH they spent is equal to BalanceDelta.amount0()

        // casting to 'uint256' is safe because amount0 is negative on a zeroForOne swap
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointsForSwap = ethSpendAmount / 5;

        // Mint the points
        _assignPoints(key.toId(), hookData, pointsForSwap);

        return (this.afterSwap.selector, 0);
    }

    function _assignPoints(
        PoolId poolId,
        bytes calldata hookData,
        uint256 points
    ) internal {
        // hookData must be exactly one abi-encoded address, otherwise nobody gets points.
        // Validate it ourselves since abi.decode would revert the whole swap on bad input.
        if (hookData.length != 32) return;

        // Decode as uint256 (can't revert on 32 bytes) and check the upper 12 bytes are
        // zero ourselves, since decoding straight to address reverts when they aren't
        uint256 word = abi.decode(hookData, (uint256));
        if (word >> 160 != 0) return;

        // Extract user address from hookData
        // casting to 'uint160' is safe because the upper bits were checked above
        // forge-lint: disable-next-line(unsafe-typecast)
        address user = address(uint160(word));

        // Zero address can't receive points
        if (user == address(0)) return;

        // Mint points to the user
        uint256 poolIdUint = uint256(PoolId.unwrap(poolId));
        _mint(user, poolIdUint, points, "");
    }
}
