// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/contracts/types/PoolId.sol";

contract PoolInitializeExampleInputs {
    //The following is for creating a pool without a hook

    using CurrencyLibrary for Currency;
    //addresses with contracts deployed

    address constant GOERLI_POOLMANAGER = address(0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b); //pool manager deployed to GOERLI
    address constant MUNI_ADDRESS = address(0xbD97BF168FA913607b996fab823F88610DCF7737); //mUNI deployed to GOERLI -- insert your own contract address here
    address constant MUSDC_ADDRESS = address(0xa468864e673a807572598AB6208E49323484c6bF); //mUSDC deployed to GOERLI -- insert your own contract address here
    // set the pool manager address
    IPoolManager manager = IPoolManager(GOERLI_POOLMANAGER);

    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );

    // / @notice Initialize a hookless pool:
    // /     0.05% swap fee
    // /     tick spacing of 10
    // /     starting price of 1:1
    function run() external {
        address token0 = address(MUSDC_ADDRESS);
        address token1 = address(MUNI_ADDRESS);
        uint24 swapFee = 500;
        int24 tickSpacing = 10;

        // floor(sqrt(1) * 2^96)
        uint160 startingPrice = 79228162514264337593543950336;

        // hookless pool doesnt expect any initialization data
        bytes memory hookData = new bytes(0);

        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: swapFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0x0))
        });

        manager.initialize(pool, startingPrice, hookData);
    }
}
