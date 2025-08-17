// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {BaseHook} from "lib/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "lib/uniswap-hooks/lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "lib/uniswap-hooks/lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "lib/uniswap-hooks/lib/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "lib/uniswap-hooks/lib/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "lib/uniswap-hooks/lib/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "lib/uniswap-hooks/lib/v4-core/src/types/BeforeSwapDelta.sol";
import {IPositionManager} from "lib/uniswap-hooks/lib/v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "lib/uniswap-hooks/lib/v4-core/src/types/Currency.sol";

interface IMsgSender {
    function msgSender() external view returns (address);
}


contract LossProtection is BaseHook {   
    using PoolIdLibrary for PoolKey;
    uint256 public constant PRICE_SCALE = 1e18;

    // Events for better logging
    event ClaimCreated(
        address indexed user,
        uint256 valueHold,
        uint256 valuePool,
        uint256 totalAddedA,
        uint256 totalAddedB,
        uint256 withdrawnA,
        uint256 withdrawnB,
        uint256 priceA,
        uint256 priceB,
        uint256 timestamp
    );

    event LiquidityEventRecorded(
        address indexed user,
        bool isAdd,
        uint256 amountA,
        uint256 amountB,
        uint256 timestamp
    );

    struct LiquidityEvent {
        bool isAdd; // true for addLiquidity, false for removeLiquidity
        uint256 amountA; // Amount of Token A added/removed (in wei)
        uint256 amountB; // Amount of Token B added/removed (in wei)
        uint256 priceA; // Price of Token A at event time (scaled, 1e18)
        uint256 priceB; // Price of Token B at event time (scaled, 1e18)
        uint256 timestamp; // Timestamp of the event
    }

    // Struct to store impermanent loss for the single removal
    struct RemovalIL {
        uint256 ilPercentage; // IL percentage (scaled to 0-100)
        uint256 timestamp; // Timestamp of the removal
    }

    // Struct to store claim information
    struct Claims {
        uint256 valueHold; // Value of holding tokens
        uint256 valuePool; // Value of pool tokens
        uint256 totalAddedA; // Total amount of token A added
        uint256 totalAddedB; // Total amount of token B added
        uint256 withdrawnA; // Amount of token A withdrawn
        uint256 withdrawnB; // Amount of token B withdrawn
        uint256 priceA; // Price of token A at claim time
        uint256 priceB; // Price of token B at claim time
        uint256 timestamp; // Timestamp of the claim
    }

    mapping(address => LiquidityEvent[]) public userEvents;
    mapping(address => RemovalIL) public userRemovalIL;
    mapping(address => Claims[]) public claimEvents;
    // User address => net tokens contributed

    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;

    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public afterAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        beforeSwapCount[key.toId()]++;
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        afterSwapCount[key.toId()]++;
        return (BaseHook.afterSwap.selector, 0);
    }

    function _beforeAddLiquidity(address, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4)
    {
        PoolId poolId = key.toId();
        beforeAddLiquidityCount[poolId]++;        
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _afterAddLiquidity(
        address posm,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        
        PoolId poolId = key.toId();
        afterAddLiquidityCount[poolId]++;
        
        uint256 amountA = uint256(delta.amount0() > 0 ? int256(delta.amount0()) : -int256(delta.amount0()));
        uint256 amountB = uint256(delta.amount1() > 0 ? int256(delta.amount1()) : -int256(delta.amount1()));
        address user = IMsgSender(posm).msgSender();

        console2.log("Miniting in pool currency0", amountA/PRICE_SCALE);
        console2.log("Miniting in pool currency1", amountB/PRICE_SCALE);

        //console2.log("address in contract positionManager", address(posm));
        //console2.log("user", user);

        userEvents[user].push(LiquidityEvent({
            isAdd: true,
            amountA: amountA,
            amountB: amountB,
            priceA: 1e18,
            priceB: 1e18,
            timestamp: block.timestamp
        }));

        // Emit event for logging
        emit LiquidityEventRecorded(user, true, amountA, amountB, block.timestamp);


        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }



    function _afterRemoveLiquidity(
        address posm,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        address user = IMsgSender(posm).msgSender();
        
        // Get actual amounts withdrawn from delta
        uint256 amountA = uint256(delta.amount0() > 0 ? int256(delta.amount0()) : -int256(delta.amount0()));
        uint256 amountB = uint256(delta.amount1() > 0 ? int256(delta.amount1()) : -int256(delta.amount1()));

        userEvents[user].push(LiquidityEvent({
                isAdd: false,
                amountA: amountA,
                amountB: amountB,
                priceA: 1e18,
                priceB: 2e18,
                timestamp: block.timestamp
            }));


        (uint256 priceA, uint256 priceB) = getOraclePrice(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));


        // Emit event for logging
        emit LiquidityEventRecorded(user, false, amountA, amountB, block.timestamp);

        calculateILForRemoval(user, amountA, amountB, priceA, priceB);
    
        beforeRemoveLiquidityCount[key.toId()]++;
        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    // Helper function to get the number of claims for a user
    function getClaimCount(address user) public view returns (uint256) {
        return claimEvents[user].length;
    }

    // Helper function to get a specific claim by index
    function getClaim(address user, uint256 index) public view returns (Claims memory) {
        require(index < claimEvents[user].length, "Claim index out of bounds");
        return claimEvents[user][index];
    }

    function calculateILForRemoval(
        address user,
        uint256 withdrawnA,
        uint256 withdrawnB,
        uint256 priceA,
        uint256 priceB
    ) internal returns (uint256 ilPercentage) {
        
        console2.log("in calculateILForRemoval");
        uint256 totalAddedA = 0;
        uint256 totalAddedB = 0;

        // Iterate through all events (excluding the current removal)
        for (uint256 i = 0; i < userEvents[user].length; i++) {
            if (userEvents[user][i].isAdd) {
                totalAddedA += userEvents[user][i].amountA;
                totalAddedB += userEvents[user][i].amountB;
            }
        }

        // Value of holding (total added tokens at removal prices)
        uint256 valueHold = (totalAddedA * priceA) / PRICE_SCALE + (totalAddedB * priceB) / PRICE_SCALE;

        // Value of withdrawn tokens (at removal prices)
        uint256 valuePool = (withdrawnA * priceA) / PRICE_SCALE + (withdrawnB * priceB) / PRICE_SCALE;

      if (valueHold > valuePool) {
            console2.log("Impermanent Loss", (valueHold - valuePool)/PRICE_SCALE);
            claimEvents[user].push(Claims({
            valueHold: valueHold,
            valuePool: valuePool,
            totalAddedA: totalAddedA,
            totalAddedB: totalAddedB,
            withdrawnA: withdrawnA,
            withdrawnB: withdrawnB,
            priceA: priceA,
            priceB: priceB,
            timestamp: block.timestamp
        }));

        // Emit event for logging
        emit ClaimCreated(
            user,
            valueHold,
            valuePool,
            totalAddedA,
            totalAddedB,
            withdrawnA,
            withdrawnB,
            priceA,
            priceB,
            block.timestamp
        );
      }  
    
    }

       function getOraclePrice(address currency0, address currency1) public pure returns (uint256 priceA, uint256 priceB) {
        // Hardcoded prices for development/testing
        // In production, this would integrate with real price oracles like Chainlink
        
        // Price of currency0 (token A) = 1e18 (1.0)
        priceA = 10e18;
        
        // Price of currency1 (token B) = 2e18 (2.0)
        priceB = 20e18;
        
        return (priceA, priceB);
        // Note: These are fixed prices for testing
        // Real implementation would fetch from oracle:
        // priceA = oracle.getPrice(currency0);
        // priceB = oracle.getPrice(currency1);
    }


        // Function to get insurance amount for a specific claim index
    function getInsuranceForClaim(address user, uint256 claimIndex) public view returns (uint256 insuranceAmount, bool hasLoss) {
        require(claimIndex < claimEvents[user].length, "Claim index out of bounds");
        
        Claims memory claim = claimEvents[user][claimIndex];
        
        // Check if user has suffered impermanent loss
        if (claim.valueHold > claim.valuePool) {
            // Calculate insurance amount
            insuranceAmount = claim.valueHold - claim.valuePool;
            hasLoss = true;
        } else {
            // No impermanent loss
            insuranceAmount = 0;
            hasLoss = false;
        }
        
        return (insuranceAmount, hasLoss);
    }

}
