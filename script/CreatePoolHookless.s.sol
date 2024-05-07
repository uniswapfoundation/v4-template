// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

contract PoolInitializeExampleInputs is Script {
    using CurrencyLibrary for Currency;

    address constant GOERLI_POOLMANAGER = address(0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b); // pool manager deployed to GOERLI
    address constant MUNI_ADDRESS = address(0xbD97BF168FA913607b996fab823F88610DCF7737); // mUNI deployed to GOERLI -- insert your own contract address here
    address constant MUSDC_ADDRESS = address(0xa468864e673a807572598AB6208E49323484c6bF); // mUSDC deployed to GOERLI -- insert your own contract address here
    address constant HOOK_ADDRESS = address(0x0); // hookless pool is 0x0!

    IPoolManager manager = IPoolManager(GOERLI_POOLMANAGER);

    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );

    function run() external {
        address token0 = address(MUSDC_ADDRESS);
        address token1 = address(MUNI_ADDRESS);
        uint24 swapFee = 500; // 0.05% fee tier
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
            hooks: IHooks(address(HOOK_ADDRESS)) // 0x0 is the hookless pool
        });

        manager.initialize(pool, startingPrice, hookData);
    }
}
