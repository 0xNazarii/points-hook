// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Dependencies
import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

// Types
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {Users} from "./utils/Types.sol";

// Libraries
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

// Contracts
import {PointsHook} from "../src/PointsHook.sol";

/// @notice Deploys v4, a TOKEN, the hook and an ETH/TOKEN pool with liquidity
abstract contract Base_Test is Test, Deployers {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant SWAP_AMOUNT = 0.001 ether;

    /// @dev 20% of SWAP_AMOUNT
    uint256 internal constant SWAP_POINTS = 0.0002 ether;

    uint64 internal constant CAMPAIGN_DURATION = 30 days;

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/

    Users internal users;

    Currency internal ethCurrency = Currency.wrap(address(0));
    Currency internal tokenCurrency;

    /// @dev Points token id for the default pool
    uint256 internal poolIdUint;

    /// @dev Campaign window of the default pool
    uint64 internal campaignStart;
    uint64 internal campaignEnd;

    /*//////////////////////////////////////////////////////////////
                               CONTRACTS
    //////////////////////////////////////////////////////////////*/

    MockERC20 internal token;
    PointsHook internal hook;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Create users
        users = Users({alice: createUser("alice"), bob: createUser("bob")});

        // Deploy PoolManager and routers
        deployFreshManagerAndRouters();

        // Deploy TOKEN and approve the routers
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));
        token.mint(address(this), 1000 ether);
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Deploy the hook to an address with its permission flags set
        address flags = address(
            uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG)
        );
        deployCodeTo("PointsHook.sol", abi.encode(manager), flags);
        hook = PointsHook(flags);

        // Initialize the ETH/TOKEN pool through the hook with a campaign starting now
        campaignStart = uint64(block.timestamp);
        campaignEnd = campaignStart + CAMPAIGN_DURATION;
        key = PoolKey(ethCurrency, tokenCurrency, 3000, 60, hook);
        hook.initializePool(key, SQRT_PRICE_1_1, campaignStart, campaignEnd);
        poolIdUint = uint256(PoolId.unwrap(key.toId()));

        // Add liquidity in [-60, 60] around price 1
        addLiquidity(key, 0.1 ether);

        // Label the contracts
        vm.label(address(token), "TOKEN");
        vm.label(address(hook), "PointsHook");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Create a user with an initial balance of 100 ether
    function createUser(
        string memory name
    ) internal returns (address payable user) {
        user = payable(makeAddr(name));
        vm.deal(user, 100 ether);
    }

    /// @dev Add liquidity to `poolKey` in [-60, 60] backed by `ethAmount` of ETH
    function addLiquidity(PoolKey memory poolKey, uint256 ethAmount) internal {
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(60),
            ethAmount
        );
        modifyLiquidityRouter.modifyLiquidity{value: ethAmount}(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    /// @dev `swapper` sells SWAP_AMOUNT of ETH for TOKEN, exact input
    function swapEthForToken(address swapper, bytes memory hookData) internal {
        vm.prank(swapper);
        swapRouter.swap{value: SWAP_AMOUNT}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(SWAP_AMOUNT),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );
    }

    /// @dev Points balance of `user` in the default pool
    function pointsOf(address user) internal view returns (uint256) {
        return hook.balanceOf(user, poolIdUint);
    }
}
