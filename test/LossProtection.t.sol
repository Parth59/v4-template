// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IHooks} from "lib/uniswap-hooks/lib/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "lib/uniswap-hooks/lib/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "lib/uniswap-hooks/lib/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "lib/uniswap-hooks/lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "lib/uniswap-hooks/lib/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "lib/uniswap-hooks/lib/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "lib/uniswap-hooks/lib/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "lib/uniswap-hooks/lib/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "lib/uniswap-hooks/lib/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "lib/uniswap-hooks/lib/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "lib/uniswap-hooks/lib/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "lib/uniswap-hooks/lib/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "lib/uniswap-hooks/lib/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {Deployers} from "./utils/Deployers.sol";

import {LossProtection} from "../src/LossProtection.sol";

contract LossProtectionTest is Test, Deployers {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    uint256 public constant PRICE_SCALE = 1e18;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    LossProtection hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifacts();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(poolManager); // Add all the necessary constructor arguments from the hook
        deployCodeTo("LossProtection.sol:LossProtection", constructorArgs, flags);
        hook = LossProtection(flags);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = LiquidityAmounts.getLiquidityForAmounts(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            100e18,
            100e18
        );

        console2.log("Initial liquidityAmount", liquidityAmount/PRICE_SCALE);

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

       
        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
  
    }
    
    function testAfterAddLiquidityHook() public {
        // Verify initial state
        assertEq(hook.afterAddLiquidityCount(poolId), 1); // From setup
        
        // Test the swap functionality
        testSwapFunctionality();

        uint128 liquidityAmount = 100e18;
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        (uint256 amount0New, uint256 amount1New) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );
        //console2.log("address positionManager", address(positionManager));
        //console2.log("user", address(this));

        console2.log("Amount of currency0 in pool after swap", amount0New/PRICE_SCALE);
        console2.log("Amount of currency0 in pool after swap", amount1New/PRICE_SCALE);

        positionManager.burn(tokenId, 0, 0, address(this), block.timestamp, Constants.ZERO_BYTES);

        console2.log("currency0 balance", currency0.balanceOf(address(this))/PRICE_SCALE);
        console2.log("currency1 balance", currency1.balanceOf(address(this))/PRICE_SCALE);
        
        // Get claim events for this address
        // Since claimEvents is a public mapping to an array, we need to access it differently
        // For now, let's just log that we're checking for claims
        console2.log("Checking for claim events...");
        
        // Get the number of claims for this address
        uint256 claimCount = hook.getClaimCount(address(this));
        console2.log("Number of claim events:", claimCount);
        
        // Log all claim events
        for (uint256 i = 0; i < claimCount; i++) {
            LossProtection.Claims memory claim = hook.getClaim(address(this), i);
            console2.log("Claim", i, "- valueHold:", claim.valueHold);
            console2.log("Claim", i, "- valuePool:", claim.valuePool);
            console2.log("Claim", i, "- totalAddedA:", claim.totalAddedA);
            console2.log("Claim", i, "- totalAddedB:", claim.totalAddedB);
            console2.log("Claim", i, "- withdrawnA:", claim.withdrawnA);
            console2.log("Claim", i, "- withdrawnB:", claim.withdrawnB);
            console2.log("Claim", i, "- priceA:", claim.priceA);
            console2.log("Claim", i, "- priceB:", claim.priceB);
            console2.log("Claim", i, "- timestamp:", claim.timestamp);
        }
    }

    function testSwapFunctionality() internal {
        
        console2.log("=== TESTING SWAP FUNCTIONALITY ===");
        
        address alice = address(0x123abcdef);
        
        // Give Alice sufficient tokens for the swap
        uint256 aliceToken0Amount = 100e18; // 100 tokens
        uint256 aliceToken1Amount = 100e18; // 100 tokens
        deal(Currency.unwrap(currency0), alice, aliceToken0Amount);
        deal(Currency.unwrap(currency1), alice, aliceToken1Amount);
        
        // Start pranking as Alice
        vm.startPrank(alice);
        
        // Approve swapRouter to spend Alice's tokens
        IERC20(Currency.unwrap(currency0)).approve(address(swapRouter), aliceToken0Amount);
        IERC20(Currency.unwrap(currency1)).approve(address(swapRouter), aliceToken1Amount);
        
        console2.log("Alice currency0 BEFORE SWAP balance", currency0.balanceOf(alice)/PRICE_SCALE);
        console2.log("Alice currency1 BEFORE SWAP balance", currency1.balanceOf(alice)/PRICE_SCALE);
        
        uint256 amountIn = 5e18;
        
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: alice,
            deadline: block.timestamp + 1
        });
        
        console2.log("token0 swapped", swapDelta.amount0());
        console2.log("token1 swapped", swapDelta.amount1());
        console2.log("Alice currency0 AFTER SWAP balance", currency0.balanceOf(alice)/PRICE_SCALE);
        console2.log("Alice currency1 AFTER SWAP balance", currency1.balanceOf(alice)/PRICE_SCALE);
        
        // Stop pranking as Alice
        vm.stopPrank();
        
        console2.log("=== SWAP TEST COMPLETED ===");
    }
}
