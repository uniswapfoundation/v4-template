// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// To run this script without Etherscan verification:
// forge script script/DeployVCOPCollateral.sol:DeployVCOPCollateral --via-ir --broadcast --fork-url https://sepolia.base.org

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {VCOPCollateralized} from "../src/VcopCollateral/VCOPCollateralized.sol";
import {VCOPOracle} from "../src/VcopCollateral/VCOPOracle.sol";
import {VCOPPriceCalculator} from "../src/VcopCollateral/VCOPPriceCalculator.sol";
import {VCOPCollateralManager} from "../src/VcopCollateral/VCOPCollateralManager.sol";
import {VCOPCollateralHook} from "../src/VcopCollateral/VCOPCollateralHook.sol";
import {DeployMockUSDC} from "./DeployMockUSDC.s.sol";
import {DeployVCOPCollateralHook} from "./DeployVCOPCollateralHook.s.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/**
 * @title DeployVCOPCollateral
 * @notice Script to deploy the VCOP collateralized system in multiple steps:
 * 1. Deploy Simulated USDC
 * 2. Deploy Collateralized VCOP
 * 3. Deploy Oracle and Price Calculator
 * 4. Deploy Hook (using HookMiner)
 * 5. Deploy Collateral Manager
 * 6. Configure collaterals and permissions
 * 7. Create pool and add liquidity
 * 8. Provision liquidity to the collateral system
 */
contract DeployVCOPCollateral is Script {
    using CurrencyLibrary for Currency;

    // Uniswap V4 Constants - Official addresses for Base Sepolia
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));
    
    // Configurable parameters for the pool
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    
    // Initial USD/COP rate (4200 COP = 1 USD)
    uint256 initialUsdToCopRate = 4200e6; // With 6 decimals
    
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
    
    // Dummy API Key to avoid verification errors
    string constant DUMMY_API_KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456";

    // Internal addresses
    address treasuryAddress;

    function run() public {
        // Set a dummy API key for Etherscan
        vm.setEnv("ETHERSCAN_API_KEY", DUMMY_API_KEY);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // If a specific private key for the hook owner is provided, use it
        uint256 hookOwnerPrivateKey = vm.envOr("HOOK_OWNER_PRIVATE_KEY", deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);
        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        
        // Use the deployer as treasury initially (could be changed later)
        treasuryAddress = deployerAddress;
        
        // Verify network and balances
        console.logString("Verifying network and balances...");
        console.logString("Deployer address:"); 
        console.logAddress(deployerAddress);
        
        // === STEP 1: Deploy Simulated USDC ===
        console.logString("=== STEP 1: Deploying Simulated USDC ===");
        
        // Deploy the simulated USDC
        DeployMockUSDC usdcDeployer = new DeployMockUSDC();
        address usdcAddress = usdcDeployer.run();
        
        // Verify deployment
        IERC20 usdc = IERC20(usdcAddress);
        uint256 usdcBalance = usdc.balanceOf(deployerAddress);
        console.logString("Simulated USDC address:"); 
        console.logAddress(usdcAddress);
        console.logString("Deployer's USDC balance:"); 
        console.logUint(usdcBalance);
        
        // Check if there's enough USDC before starting
        require(usdcBalance >= stablecoinLiquidity + psmUsdcFunding, "Insufficient USDC for the complete system.");
        
        // References to external Uniswap contracts
        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        PositionManager positionManager = PositionManager(payable(positionManagerAddress));
        
        // === STEP 2: Deploy Collateralized VCOP ===
        console.logString("=== STEP 2: Deploying Collateralized VCOP ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Collateralized VCOP
        VCOPCollateralized vcop = new VCOPCollateralized();
        
        console.logString("Collateralized VCOP deployed at:"); 
        console.logAddress(address(vcop));
        
        vm.stopBroadcast();
        
        // === STEP 3: Deploy Oracle and Price Calculator ===
        console.logString("=== STEP 3: Deploying Oracle and Price Calculator ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy oracle with initial rate of 4200 COP = 1 USD
        VCOPOracle oracle = new VCOPOracle(
            initialUsdToCopRate,
            poolManagerAddress,
            address(vcop),
            usdcAddress,
            lpFee,
            tickSpacing,
            address(0) // Hook will be configured later
        );
        
        console.logString("Oracle deployed at:"); 
        console.logAddress(address(oracle));
        console.logString("Initial USD/COP rate:");
        console.logUint(initialUsdToCopRate / 1e6);
        
        vm.stopBroadcast();
        
        // Save addresses for the next script
        vm.setEnv("VCOP_ADDRESS", vm.toString(address(vcop)));
        vm.setEnv("ORACLE_ADDRESS", vm.toString(address(oracle)));
        vm.setEnv("USDC_ADDRESS", vm.toString(usdcAddress));
        
        // === STEP 5: Deploy VCOPCollateralManager ===
        console.logString("=== STEP 5: Deploying Collateral Manager ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the collateral manager
        VCOPCollateralManager collateralManager = new VCOPCollateralManager(
            address(vcop),
            address(oracle)
        );
        
        console.logString("Collateral Manager deployed at:");
        console.logAddress(address(collateralManager));
        
        vm.stopBroadcast();
        
        // Save manager address so the hook can use it during deployment
        vm.setEnv("COLLATERAL_MANAGER_ADDRESS", vm.toString(address(collateralManager)));
        
        // === STEP 4: Deploy Hook with specialized script ===
        console.logString("=== STEP 4: Deploying Hook with specialized script ===");
        
        // Run the specific script to deploy the hook
        DeployVCOPCollateralHook hookDeployer = new DeployVCOPCollateralHook();
        address hookAddress = hookDeployer.run();
        
        // Get reference to deployed hook
        VCOPCollateralHook hook = VCOPCollateralHook(hookAddress);
        
        console.logString("Hook deployed at:");
        console.logAddress(address(hook));
        
        // Save hook address for future scripts
        vm.setEnv("HOOK_ADDRESS", vm.toString(address(hook)));
        
        // === STEP 6: Configure Cross-References ===
        console.logString("=== STEP 6: Configuring Cross-References ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Verify current hook owner
        address hookOwner;
        try hook.owner() returns (address currentOwner) {
            hookOwner = currentOwner;
            console.logString("Current hook owner:");
            console.logAddress(hookOwner);
            
            // Transfer ownership to deployer if necessary
            if (hookOwner != deployerAddress) {
                console.logString("Transferring hook ownership to deployer...");
                
                // First we need to broadcast from the current owner's address
                vm.stopBroadcast();
                vm.startBroadcast(hookOwnerPrivateKey);
                
                // Transfer ownership to deployer
                hook.transferOwnership(deployerAddress);
                console.logString("Ownership transferred to deployer");
                
                // Return to deployer
                vm.stopBroadcast();
                vm.startBroadcast(deployerPrivateKey);
            }
        } catch {
            console.logString("Could not get hook owner, possibly not Ownable");
        }
        
        // 1. Configure the hook to recognize the collateralManager (if not done in the constructor)
        if (hook.collateralManagerAddress() == address(0)) {
            try hook.setCollateralManager(address(collateralManager)) {
                console.logString("CollateralManager assigned to hook successfully");
            } catch (bytes memory errorData) {
                console.logString("Error assigning CollateralManager to hook:");
                console.logBytes(errorData);
            }
        } else {
            console.logString("Hook already has CollateralManager configured:");
            console.logAddress(hook.collateralManagerAddress());
        }
        
        // 2. Configure the collateralManager to recognize the hook
        collateralManager.setPSMHook(address(hook));
        
        // 3. Token -> Manager
        vcop.setCollateralManager(address(collateralManager));
        
        // 4. Mint/burn permissions to manager
        vcop.setMinter(address(collateralManager), true);
        vcop.setBurner(address(collateralManager), true);
        
        // 5. Fee collector
        collateralManager.setFeeCollector(treasuryAddress);
        
        vm.stopBroadcast();
        
        // === STEP 7: Configure Collaterals and Permissions ===
        console.logString("=== STEP 7: Configuring Collaterals and Permissions ===");
        vm.startBroadcast(deployerPrivateKey);
        
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
            address(vcop),
            usdcAddress,
            lpFee,
            tickSpacing,
            address(hook),
            initialUsdToCopRate
        );
        
        oracle.setPriceCalculator(address(priceCalculator));
        
        console.logString("USDC collateral configured with ratio:");
        console.logUint(collateralRatio);
        console.logString("Liquidation threshold:");
        console.logUint(liquidationThreshold);
        console.logString("Price calculator updated at:");
        console.logAddress(address(priceCalculator));
        
        vm.stopBroadcast();
        
        // === STEP 8: Create Pool and Add Liquidity ===
        console.logString("=== STEP 8: Creating Pool and adding liquidity ===");
        console.logString("USDC liquidity to add:"); 
        console.logUint(stablecoinLiquidity / 1e6); 
        console.logString("USDC");
        console.logString("VCOP liquidity to add:"); 
        console.logUint(vcopLiquidity / 1e6); 
        console.logString("VCOP");
        console.logString("VCOP/USDC ratio:"); 
        console.logUint(vcopLiquidity / stablecoinLiquidity);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Create Currency for VCOP and USDC
        Currency vcopCurrency = Currency.wrap(address(vcop));
        Currency usdcCurrency = Currency.wrap(usdcAddress);
        
        // Ensure currencies are in correct order (lower address first)
        Currency currency0;
        Currency currency1;
        bool vcopIsToken0;
        
        if (address(vcop) < usdcAddress) {
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
        
        // Prepare multicall parameters
        bytes[] memory params = new bytes[](2);
        
        // Initialize pool
        params[0] = abi.encodeWithSelector(
            positionManager.initializePool.selector, 
            poolKey, 
            startingPrice, 
            hookData
        );
        
        // Prepare parameters to add liquidity
        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            poolKey, 
            tickLower, 
            tickUpper, 
            liquidity, 
            amount0Max, 
            amount1Max, 
            deployerAddress,
            hookData
        );
        
        // Add liquidity
        params[1] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector, 
            abi.encode(actions, mintParams), 
            block.timestamp + 60
        );
        
        // Approve tokens so PositionManager can use them
        _approveTokens(address(vcop), usdcAddress, address(positionManager));
        
        // Execute multicall to create pool and add liquidity
        positionManager.multicall(params);
        
        // Verify balances after adding liquidity
        uint256 vcopBalanceDeployer = vcop.balanceOf(deployerAddress);
        uint256 usdcBalanceDeployer = usdc.balanceOf(deployerAddress);
        
        console.logString("Deployer's VCOP balance after adding liquidity:");
        console.logUint(vcopBalanceDeployer);
        console.logString("Deployer's USDC balance after adding liquidity:");
        console.logUint(usdcBalanceDeployer);
        
        console.logString("Pool created and initial liquidity added successfully");
        
        vm.stopBroadcast();
        
        // === STEP 9: Provision Liquidity to the Collateral System ===
        console.logString("=== STEP 9: Provisioning Liquidity to the Collateral System ===");
        vm.startBroadcast(deployerPrivateKey);
        
        // Transfer USDC to collateralManager for PSM
        usdc.transfer(address(collateralManager), psmUsdcFunding);
        
        // Mint VCOP to collateralManager for PSM
        vcop.mint(address(collateralManager), psmVcopFunding);
        
        // Activate the PSM module in collateralManager
        collateralManager.setPSMReserveStatus(usdcAddress, true);
        
        // Verify hook owner again
        try hook.owner() returns (address currentOwner) {
            console.logString("Current hook owner in step 9:");
            console.logAddress(currentOwner);
            
            if (currentOwner != deployerAddress) {
                console.logString("WARNING: Hook does not belong to the deployer");
                // We can't use HOOK_OWNER_PRIVATE_KEY here because we already used the PSM
                // Report the issue so it can be fixed manually
            }
        } catch {
            console.logString("Could not verify the hook owner");
        }
        
        // Verify that the hook has appropriate permissions
        // Ensure the hook recognizes the manager
        try hook.collateralManagerAddress() returns (address currentManager) {
            console.logString("Current CollateralManager in the hook:");
            console.logAddress(currentManager);
            
            if (currentManager != address(collateralManager)) {
                console.logString("Trying to update the CollateralManager in the hook...");
                try hook.setCollateralManager(address(collateralManager)) {
                    console.logString("CollateralManager updated in the hook successfully");
                } catch (bytes memory errorData) {
                    console.logString("Error updating CollateralManager in the hook:");
                    console.logBytes(errorData);
                    console.logString("This may be due to a permissions issue");
                }
            } else {
                console.logString("Hook already has the CollateralManager configured correctly");
            }
        } catch {
            console.logString("Could not verify the CollateralManager in the hook");
        }
        
        // Configure PSM in the hook
        try hook.updatePSMParameters(
            psmFee, 
            psmVcopFunding / 10 // Limit individual operations to 10% of the fund
        ) {
            console.logString("PSM parameters updated successfully");
        } catch (bytes memory errorData) {
            console.logString("Error updating PSM parameters:");
            console.logBytes(errorData);
            
            // In case of error, verify the hook owner
            try hook.owner() returns (address hookOwner) {
                console.logString("Hook owner:");
                console.logAddress(hookOwner);
                
                console.logString("Deployer address:");
                console.logAddress(deployerAddress);
                
                if (hookOwner != deployerAddress) {
                    console.logString("The hook owner is not the deployer. This must be fixed manually.");
                }
            } catch {
                console.logString("Could not get the hook owner");
            }
        }
        
        console.logString("Liquidity provisioned to PSM:");
        console.logString("USDC in PSM:");
        console.logUint(psmUsdcFunding / 1e6);
        console.logString("VCOP in PSM:");
        console.logUint(psmVcopFunding / 1e6);
        
        // Verify prices and parity
        console.logString("=== Final Price Verification ===");
        
        try priceCalculator.calculateAllPrices() returns (
            uint256 vcopToUsdPrice, 
            uint256 vcopToCopPrice, 
            int24 currentTick, 
            bool parityStatus
        ) {
            console.logString("Calculated VCOP/USDC price:");
            console.logUint(vcopToUsdPrice / 1e6);
            console.logString("Calculated VCOP/COP price:");
            console.logUint(vcopToCopPrice / 1e6);
            console.logString("Current pool tick:");
            console.logInt(currentTick);
            console.logString("Is VCOP at 1:1 parity with COP?");
            console.logBool(parityStatus);
        } catch {
            console.logString("Could not calculate all prices. The pool needs time to fully initialize.");
        }
        
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
        console.logUint((vcopBalanceAfter - vcopBalanceDeployer) / 1e6);
        
        console.logString("VCOP Collateralized System deployed successfully!");
        
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