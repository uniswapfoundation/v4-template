// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPPriceCalculator} from "../src/VcopCollateral/VCOPPriceCalculator.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";
import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";
import {DeployVCOPCollateralHook} from "./DeployVCOPCollateralHook.s.sol";

// Simplified interface for PositionManager
interface IPositionManager {
    function multicall(bytes[] calldata data) external returns (bytes[] memory);
    function unlock(bytes calldata data) external returns (bytes memory);
    function modifyLiquidities(bytes memory data, uint256 deadline) external returns (bytes memory result);
}

/**
 * @title ConfigureVCOPSystem
 * @notice Script to configure the VCOP system after the base deployment
 * @dev To run: forge script script/ConfigureVCOPSystem.sol:ConfigureVCOPSystem --via-ir --broadcast --fork-url https://sepolia.base.org
 */
contract ConfigureVCOPSystem is Script {
    using CurrencyLibrary for Currency;
    
    // Uniswap V4 Constants - Official addresses for Base Sepolia
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
    
    // Addresses of deployed contracts (obtained from logs)
    address constant DEPLOYED_USDC_ADDRESS = 0x9e58c822c643779fe1a64aCB93d9c22D701eEBB0;
    address constant DEPLOYED_VCOP_ADDRESS = 0x092C440a765F09B2f4Fb99C6cfF73eC0EaDb0cb9;
    address constant DEPLOYED_ORACLE_ADDRESS = 0x1B47cF922B3A0ba5CE7A7B3e9E2b3792ad119D02;
    address constant DEPLOYED_COLLATERAL_MANAGER_ADDRESS = 0x0F97fE0C0390479E3271498a0a2EF7E023Ec19ca;
    
    // Configurable parameters for the pool
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    
    // For a 1:4200 ratio, we use an appropriate initial price
    uint160 startingPrice;
    
    // Configuration for initial liquidity position
    uint256 stablecoinLiquidity = 100_000 * 1e6;  // 100,000 USDC
    uint256 vcopLiquidity = 420_000_000 * 1e6;    // 420,000,000 VCOP (ratio 4200:1)
    
    // Configuration for PSM (Peg Stability Module)
    uint256 psmUsdcFunding = 100_000 * 1e6;      // 100,000 USDC for PSM
    uint256 psmVcopFunding = 420_000_000 * 1e6;  // 420,000,000 VCOP for PSM
    uint256 psmFee = 1000;                       // 0.1% fee (base 1e6)
    
    // Collateralization parameters
    uint256 collateralRatio = 1500000;           // 150% (1.5 * 1e6)
    uint256 liquidationThreshold = 1200000;      // 120% (1.2 * 1e6)
    uint256 mintFee = 1000;                      // 0.1% (1e6 basis)
    uint256 burnFee = 1000;                      // 0.1% (1e6 basis)
    
    // Ticks for liquidity range
    int24 tickLower;
    int24 tickUpper;

    // Loads addresses from the previous deployment
    function loadAddresses() internal view returns (
        address usdcAddress,
        address vcopAddress,
        address oracleAddress,
        address collateralManagerAddress
    ) {
        // Try to load from environment variables
        try vm.envAddress("USDC_ADDRESS") returns (address _usdcAddress) {
            if (_usdcAddress != address(0)) {
                usdcAddress = _usdcAddress;
                console.logString("USDC address loaded from environment variables");
            } else {
                usdcAddress = DEPLOYED_USDC_ADDRESS;
                console.logString("USDC address using hardcoded value");
            }
        } catch {
            usdcAddress = DEPLOYED_USDC_ADDRESS;
            console.logString("USDC address using hardcoded value");
        }

        try vm.envAddress("VCOP_ADDRESS") returns (address _vcopAddress) {
            if (_vcopAddress != address(0)) {
                vcopAddress = _vcopAddress;
                console.logString("VCOP address loaded from environment variables");
            } else {
                vcopAddress = DEPLOYED_VCOP_ADDRESS;
                console.logString("VCOP address using hardcoded value");
            }
        } catch {
            vcopAddress = DEPLOYED_VCOP_ADDRESS;
            console.logString("VCOP address using hardcoded value");
        }

        try vm.envAddress("ORACLE_ADDRESS") returns (address _oracleAddress) {
            if (_oracleAddress != address(0)) {
                oracleAddress = _oracleAddress;
                console.logString("Oracle address loaded from environment variables");
            } else {
                oracleAddress = DEPLOYED_ORACLE_ADDRESS;
                console.logString("Oracle address using hardcoded value");
            }
        } catch {
            oracleAddress = DEPLOYED_ORACLE_ADDRESS;
            console.logString("Oracle address using hardcoded value");
        }

        try vm.envAddress("COLLATERAL_MANAGER_ADDRESS") returns (address _collateralManagerAddress) {
            if (_collateralManagerAddress != address(0)) {
                collateralManagerAddress = _collateralManagerAddress;
                console.logString("CollateralManager address loaded from environment variables");
            } else {
                collateralManagerAddress = DEPLOYED_COLLATERAL_MANAGER_ADDRESS;
                console.logString("CollateralManager address using hardcoded value");
            }
        } catch {
            collateralManagerAddress = DEPLOYED_COLLATERAL_MANAGER_ADDRESS;
            console.logString("CollateralManager address using hardcoded value");
        }
        
        // Show the addresses that will be used
        console.logString("=== Contract addresses ===");
        console.logString("USDC:"); 
        console.logAddress(usdcAddress);
        console.logString("VCOP:"); 
        console.logAddress(vcopAddress);
        console.logString("Oracle:"); 
        console.logAddress(oracleAddress);
        console.logString("CollateralManager:"); 
        console.logAddress(collateralManagerAddress);
        
        // Verify that all addresses are valid
        require(usdcAddress != address(0), "Invalid USDC_ADDRESS");
        require(vcopAddress != address(0), "Invalid VCOP_ADDRESS");
        require(oracleAddress != address(0), "Invalid ORACLE_ADDRESS");
        require(collateralManagerAddress != address(0), "Invalid COLLATERAL_MANAGER_ADDRESS");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address treasuryAddress = deployerAddress;
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        
        // Load addresses from the base deployment
        (
            address usdcAddress,
            address vcopAddress,
            address oracleAddress,
            address collateralManagerAddress
        ) = loadAddresses();
        
        // Load deployed contracts
        IERC20 usdc = IERC20(usdcAddress);
        VCOPCollateralized vcop = VCOPCollateralized(vcopAddress);
        VCOPOracle oracle = VCOPOracle(oracleAddress);
        VCOPCollateralManager collateralManager = VCOPCollateralManager(collateralManagerAddress);
        
        console.logString("=== STEP 1: Deploying Hook with specialized script ===");
        
        // Save addresses in environment variables for the hook
        vm.setEnv("COLLATERAL_MANAGER_ADDRESS", vm.toString(address(collateralManager)));
        vm.setEnv("VCOP_ADDRESS", vm.toString(address(vcop)));
        vm.setEnv("USDC_ADDRESS", vm.toString(address(usdc)));
        vm.setEnv("ORACLE_ADDRESS", vm.toString(address(oracle)));
        
        // Deploy hook - this deployer will be the owner, avoiding permission issues
        DeployVCOPCollateralHook hookDeployer = new DeployVCOPCollateralHook();
        address hookAddress = hookDeployer.run();
        VCOPCollateralHook hook = VCOPCollateralHook(hookAddress);
        
        console.logString("Hook deployed at:");
        console.logAddress(hookAddress);
        
        // === STEP 2: Configure Cross-References ===
        console.logString("=== STEP 2: Configuring Cross-References ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Verify the hook owner
        try hook.owner() returns (address hookOwner) {
            console.logString("Current hook owner:");
            console.logAddress(hookOwner);
            
            if (hookOwner != deployerAddress) {
                console.logString("WARNING: The hook does not belong to the deployer");
                console.logString("This must be fixed manually before continuing");
                return;
            }
        } catch {
            console.logString("Could not verify the hook owner");
            return;
        }
        
        // 1. Configure the hook to recognize the collateralManager
        try hook.setCollateralManager(collateralManagerAddress) {
            console.logString("CollateralManager configured in the hook successfully");
        } catch (bytes memory errorData) {
            console.logString("Error configuring CollateralManager in the hook:");
            console.logBytes(errorData);
            return;
        }
        
        // 2. Configure the collateralManager to recognize the hook
        collateralManager.setPSMHook(hookAddress);
        
        // 3. Token -> Manager
        vcop.setCollateralManager(collateralManagerAddress);
        
        // 4. Mint/burn permissions to manager
        vcop.setMinter(collateralManagerAddress, true);
        vcop.setBurner(collateralManagerAddress, true);
        
        // 5. Fee collector
        collateralManager.setFeeCollector(treasuryAddress);
        
        // === STEP 3: Configure Collaterals and Prices ===
        console.logString("=== STEP 3: Configuring Collaterals and Prices ===");
        
        // Configure USDC as collateral
        collateralManager.configureCollateral(
            usdcAddress,
            collateralRatio, // 150%
            mintFee,         // 0.1%
            burnFee,         // 0.1%
            liquidationThreshold, // 120%
            true // active
        );
        
        // Register identifier for automated deployment
        collateralManager.registerTokenIdentifier(usdcAddress, "USDC");
        
        // Update price calculator with hook address
        VCOPPriceCalculator priceCalculator = new VCOPPriceCalculator(
            poolManagerAddress,
            vcopAddress,
            usdcAddress,
            lpFee,
            tickSpacing,
            hookAddress,
            4200e6 // Initial USD/COP rate
        );
        
        oracle.setPriceCalculator(address(priceCalculator));
        
        console.logString("Collaterals configured and price calculator updated");
        
        // === STEP 4: Create Pool and Add Liquidity ===
        console.logString("=== STEP 4: Creating Pool and adding liquidity ===");
        console.logString("USDC liquidity to add:"); 
        console.logUint(stablecoinLiquidity / 1e6); 
        console.logString("USDC");
        console.logString("VCOP liquidity to add:"); 
        console.logUint(vcopLiquidity / 1e6); 
        console.logString("VCOP");
        console.logString("VCOP/USDC ratio:"); 
        console.logUint(vcopLiquidity / stablecoinLiquidity);
        
        // Create Currency for VCOP and USDC
        Currency vcopCurrency = Currency.wrap(vcopAddress);
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        // Ensure currencies are in correct order (lower address first)
        Currency currency0;
        Currency currency1;
        bool vcopIsToken0;
        
        // We need to ensure that currency0 has a lower address than currency1
        if (vcopAddress < usdcAddress) {
            // If VCOP has a lower address, it should be currency0
            currency0 = vcopCurrency;
            currency1 = usdcCurrency;
            vcopIsToken0 = true;
            
            // If VCOP is token0, then for a ratio of 4200 VCOP = 1 USDC
            // The price must be low (1/4200)
            int24 targetTick = -83000;
            startingPrice = TickMath.getSqrtPriceAtTick(targetTick);
            
            // For VCOP/USDC, we widen the tick range
            tickLower = targetTick - 6000; 
            tickUpper = targetTick + 6000;
            
        } else {
            // If USDC has a lower address, it should be currency0
            currency0 = usdcCurrency;
            currency1 = vcopCurrency;
            vcopIsToken0 = false;
            
            // If USDC is token0, then for a ratio of 4200 VCOP = 1 USDC
            // The price must be high (4200)
            int24 targetTick = 83000;
            startingPrice = TickMath.getSqrtPriceAtTick(targetTick);
            
            // For USDC/VCOP, we widen the tick range
            tickLower = targetTick - 6000;
            tickUpper = targetTick + 6000;
        }
        
        // Adjust ticks to be multiples of tickSpacing
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;
        
        console.logString("VCOP is token0:");
        console.logBool(vcopIsToken0);
        console.logString("Initial price:");
        console.logUint(uint256(startingPrice));
        console.logString("Lower tick:");
        console.logInt(tickLower);
        console.logString("Upper tick:");
        console.logInt(tickUpper);
        
        // Create the PoolKey structure
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
        
        bytes memory hookData = new bytes(0);
        
        // Prepare amounts for initial liquidity
        uint256 amount0Max = vcopIsToken0 ? vcopLiquidity : stablecoinLiquidity;
        uint256 amount1Max = vcopIsToken0 ? stablecoinLiquidity : vcopLiquidity;
        
        console.logString("Maximum token0 amount:");
        console.logUint(amount0Max);
        console.logString("Maximum token1 amount:");
        console.logUint(amount1Max);
        
        // Mint VCOP for the deployer to add liquidity
        vcop.mint(deployerAddress, vcopLiquidity);
        
        // Calculate liquidity
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Max,
            amount1Max
        );
        
        console.logString("Calculated liquidity:");
        console.logUint(uint256(liquidity));
        
        // Initialize pool directly with the Pool Manager
        console.logString("Initializing pool directly with Pool Manager...");
        
        try IPoolManager(poolManagerAddress).initialize(poolKey, startingPrice) returns (int24 initializedTick) {
            console.logString("Pool initialized successfully");
            console.logString("Initial tick:");
            console.logInt(initializedTick);
            
            // Now add liquidity
            console.logString("Adding liquidity...");
            
            // Approve tokens so PositionManager can use them
            _approveTokens(vcopAddress, usdcAddress, positionManagerAddress);
            
            // Following the exact pattern from the Uniswap v4 documentation:
            // 1. Prepare actions for minting and settling
            bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
            
            // 2. Prepare mint parameters
            bytes[] memory mintParams = new bytes[](2);
            mintParams[0] = abi.encode(
                poolKey, 
                tickLower, 
                tickUpper, 
                liquidity, 
                amount0Max, 
                amount1Max, 
                deployerAddress,
                hookData
            );
            mintParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);
            
            // 3. Prepare parameters for modifyLiquidities
            bytes[] memory params = new bytes[](1);
            uint256 deadline = block.timestamp + 60;
            
            params[0] = abi.encodeWithSelector(
                IPositionManager(positionManagerAddress).modifyLiquidities.selector,
                abi.encode(actions, mintParams),
                deadline
            );
            
            // 4. Execute multicall to add liquidity
            try IPositionManager(payable(positionManagerAddress)).multicall(params) {
                console.logString("Liquidity added successfully");
            } catch (bytes memory errorData) {
                console.logString("Error adding liquidity:");
                console.logBytes(errorData);
            }
        } catch (bytes memory errorData) {
            console.logString("Error initializing pool:");
            console.logBytes(errorData);
            return;
        }
        
        // === STEP 5: Provision Liquidity to the Collateral System ===
        console.logString("=== STEP 5: Provisioning Liquidity to the Collateral System ===");
        
        // Transfer USDC to collateralManager for PSM
        usdc.transfer(address(collateralManager), psmUsdcFunding);
        
        // Register the USDC funds in the PSM mapping
        usdc.approve(address(collateralManager), psmUsdcFunding);
        collateralManager.addPSMFunds(usdcAddress, psmUsdcFunding);
        
        // Mint VCOP to collateralManager for PSM
        vcop.mint(address(collateralManager), psmVcopFunding);
        
        // Activate PSM module in collateralManager first (required)
        collateralManager.setPSMReserveStatus(usdcAddress, true);
        
        // Register VCOP amount in PSM reserves using the initialization function 
        collateralManager.initializePSMVcop(usdcAddress, psmVcopFunding);
        
        // Configure PSM in the hook
        try hook.updatePSMParameters(
            psmFee, 
            psmVcopFunding / 10 // Limit individual operations to 10% of the fund
        ) {
            console.logString("PSM parameters updated successfully");
        } catch (bytes memory errorData) {
            console.logString("Error updating PSM parameters:");
            console.logBytes(errorData);
            return;
        }
        
        console.logString("Liquidity provisioned to PSM:");
        console.logString("USDC in PSM:");
        console.logUint(psmUsdcFunding / 1e6);
        console.logString("VCOP in PSM:");
        console.logUint(psmVcopFunding / 1e6);
        
        // Create a test position with collateral
        console.logString("=== Creating Test Position ===");
        
        // Approve USDC for collateralManager
        uint256 testCollateralAmount = 1000 * 1e6; // 1000 USDC
        usdc.approve(address(collateralManager), testCollateralAmount);
        
        // Calculate maximum VCOP for this collateral
        uint256 maxVcop = collateralManager.getMaxVCOPforCollateral(usdcAddress, testCollateralAmount);
        console.logString("Maximum VCOP for 1000 USDC collateral:");
        console.logUint(maxVcop / 1e6);
        
        // Create position
        collateralManager.createPosition(usdcAddress, testCollateralAmount, maxVcop);
        
        // Verify VCOP received
        uint256 vcopBalanceAfter = vcop.balanceOf(deployerAddress);
        console.logString("VCOP received from collateralization:");
        
        // Fix: Check before subtracting to avoid underflow
        if (vcopBalanceAfter >= vcopLiquidity) {
            console.logUint((vcopBalanceAfter - vcopLiquidity) / 1e6);
        } else {
            console.logString("Current balance lower than initial liquidity. Current balance:");
            console.logUint(vcopBalanceAfter / 1e6);
            console.logString("Initial liquidity:");
            console.logUint(vcopLiquidity / 1e6);
        }
        
        console.logString("VCOP Collateralized System configured successfully!");
        
        vm.stopBroadcast();
    }
    
    // Helper function to encode mint liquidity parameters
    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        return (actions, params);
    }
    
    // Approve tokens for Permit2 and PositionManager
    function _approveTokens(address vcopAddress, address usdcAddress, address positionManagerAddress) internal {
        // Approve VCOP
        IERC20(vcopAddress).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(vcopAddress, positionManagerAddress, type(uint160).max, type(uint48).max);
        
        // Approve USDC
        IERC20(usdcAddress).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(usdcAddress, positionManagerAddress, type(uint160).max, type(uint48).max);
    }
} 