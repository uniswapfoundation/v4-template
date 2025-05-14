// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {VCOPPriceCalculator} from "./VCOPPriceCalculator.sol";

/**
 * @title VCOPOracle
 * @notice Oracle to provide VCOP price in relation to Colombian Peso (COP) and US Dollar (USD)
 * @dev Uses 6 decimals to maintain consistency with VCOP and USDC
 */
contract VCOPOracle is Ownable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // Uniswap v4 Pool Manager
    IPoolManager public immutable poolManager;
    
    // Token addresses for the pool
    address public immutable vcopAddress;
    address public immutable usdcAddress;
    
    // Pool parameters
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    address public immutable hookAddress;
    
    // Indicates if VCOP is token0 in the pool
    bool public isVCOPToken0;
    
    // US Dollar to Colombian Peso rate (with 6 decimals)
    // 4200 COP = 1 USD, so 4200 * 1e6 = 4.2e9
    uint256 private _usdToCopRate = 4200 * 1e6;
    
    // VCOP to COP conversion factor (with 6 decimals)
    // 1 VCOP = 1 COP initially, so 1e6
    uint256 private _vcopToCopRate = 1e6;
    
    // Price calculator (implementation using TestPoolPrice logic)
    VCOPPriceCalculator public priceCalculator;

    // Events emitted when prices are updated
    event UsdToCopRateUpdated(uint256 oldRate, uint256 newRate);
    event VcopToCopRateUpdated(uint256 oldRate, uint256 newRate);
    
    // New events for detailed tracking
    event PriceRequested(address requester, string rateType);
    event PriceProvided(address requester, string rateType, uint256 rate);
    event PoolPriceUpdated(uint256 sqrtPriceX96, uint256 price);
    event PriceCalculatorSet(address calculator);

    /**
     * @dev Constructor that initializes the oracle with initial rates and pool configuration
     * @param initialUsdToCopRate Initial USD/COP rate (in 6 decimal format)
     * @param _poolManager Address of the Uniswap v4 PoolManager
     * @param _vcopAddress Address of the VCOP token
     * @param _usdcAddress Address of the USDC token
     * @param _fee Pool fee (e.g., 3000 for 0.3%)
     * @param _tickSpacing Pool tick spacing
     * @param _hookAddress Hook address
     */
    constructor(
        uint256 initialUsdToCopRate,
        address _poolManager,
        address _vcopAddress,
        address _usdcAddress,
        uint24 _fee,
        int24 _tickSpacing,
        address _hookAddress
    ) Ownable(msg.sender) {
        if (initialUsdToCopRate > 0) {
            _usdToCopRate = initialUsdToCopRate;
        }
        
        poolManager = IPoolManager(_poolManager);
        vcopAddress = _vcopAddress;
        usdcAddress = _usdcAddress;
        fee = _fee;
        tickSpacing = _tickSpacing;
        hookAddress = _hookAddress;
        
        // Determine if VCOP is token0 or token1 (lexicographic ordering)
        isVCOPToken0 = uint160(_vcopAddress) < uint160(_usdcAddress);
        
        console.log("VCOPOracle initialized with Uniswap v4");
        console.log("Initial USD/COP rate:", _usdToCopRate);
        console.log("Initial VCOP/COP rate:", _vcopToCopRate);
        console.log("VCOP is token0:", isVCOPToken0);
    }
    
    /**
     * @dev Gets the USD to COP exchange rate (view version)
     * @return The rate in 6 decimal format (without modifying state)
     */
    function getUsdToCopRateView() public view returns (uint256) {
        return _usdToCopRate;
    }
    
    /**
     * @dev Gets the VCOP to COP exchange rate (view version)
     * @return The rate in 6 decimal format (without modifying state)
     */
    function getVcopToCopRateView() public view returns (uint256) {
        return _vcopToCopRate;
    }
    
    /**
     * @dev Sets the external price calculator
     * @param _calculator Address of the price calculator
     */
    function setPriceCalculator(address _calculator) external onlyOwner {
        require(_calculator != address(0), "Calculator address cannot be zero");
        priceCalculator = VCOPPriceCalculator(_calculator);
        emit PriceCalculatorSet(_calculator);
        
        console.log("Price calculator set:", _calculator);
    }
    
    /**
     * @dev Creates the PoolKey structure for the VCOP-USDC pool
     */
    function _createPoolKey() internal view returns (PoolKey memory) {
        Currency currency0;
        Currency currency1;
        
        // Assign tokens in the correct order
        if (isVCOPToken0) {
            currency0 = Currency.wrap(vcopAddress);
            currency1 = Currency.wrap(usdcAddress);
        } else {
            currency0 = Currency.wrap(usdcAddress);
            currency1 = Currency.wrap(vcopAddress);
        }
        
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
    }
    
    /**
     * @dev Gets the VCOP/USDC price directly from the Uniswap v4 pool
     * @return The VCOP/USDC price in 6 decimal format
     */
    function getVcopToUsdPriceFromPool() public view returns (uint256) {
        // If we have the price calculator, use it
        if (address(priceCalculator) != address(0)) {
            (uint256 vcopToUsdPrice, ) = priceCalculator.getVcopToUsdPriceFromPool();
            console.log("ORACLE: Obtained VCOP/USD price via calculator:", vcopToUsdPrice);
            return vcopToUsdPrice;
        }
        
        // Inherited implementation as fallback
        PoolKey memory poolKey = _createPoolKey();
        PoolId poolId = poolKey.toId();
        
        // Get sqrtPriceX96 from the pool
        (uint160 sqrtPriceX96, int24 tick, , ) = poolManager.getSlot0(poolId);
        console.log("ORACLE: Pool sqrtPriceX96:", uint256(sqrtPriceX96));
        console.log("ORACLE: Pool tick:", tick);
        
        // Calculate price from sqrtPriceX96
        uint256 price;
        
        if (isVCOPToken0) {
            // If VCOP is token0, price is 1/price (USDC/VCOP)
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e6) >> 192;
            console.log("ORACLE: Intermediate price (token0):", price);
            price = (1e12 * 1e6) / price; // Invert and adjust to 6 decimals (1e6)
        } else {
            // If VCOP is token1, price is price (VCOP/USDC)
            price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e6) >> 192;
            console.log("ORACLE: Intermediate price (token1):", price);
        }
        
        console.log("ORACLE: Calculated VCOP/USD price (6 decimals):", price);
        return price;
    }

    /**
     * @dev Updates exchange rates based on real pool prices
     */
    function updateRatesFromPool() public returns (uint256, uint256) {
        // Get VCOP/USDC price from the pool using calculator if available
        uint256 vcopToUsdPrice;
        int24 currentTick;
        
        if (address(priceCalculator) != address(0)) {
            (vcopToUsdPrice, currentTick) = priceCalculator.getVcopToUsdPriceFromPool();
        } else {
            vcopToUsdPrice = getVcopToUsdPriceFromPool();
            currentTick = 0; // We can't get the tick without calculator
        }
        
        console.log("========== UPDATING RATES ==========");
        console.log("Pool VCOP/USD price:", vcopToUsdPrice);
        console.log("Current USD/COP rate:", _usdToCopRate);
        
        // Simplified VCOP/COP calculation
        // If 1 USD = 4200 COP (ideal rate) and we have X VCOP per 1 USDC (pool price)
        // Then VCOP/COP = (1 USD / X VCOP) * (4200 COP / 1 USD) = 4200/X
        
        // Calculate VCOP/COP as the relationship between reference rate and current rate
        // _usdToCopRate is the price of 1 USD in COP (e.g., 4200e6)
        // vcopToUsdPrice is the price of 1 USDC in VCOP (e.g., 4022e6)
        
        uint256 oldVcopToCopRate = _vcopToCopRate;
        
        // If 1 USDC = 4022 VCOP and 1 USDC = 4200 COP, then:
        // 1 VCOP = (4200/4022) COP ≈ 1.04 COP
        if (vcopToUsdPrice > 0) {
            // Detailed calculation with intermediate values
            uint256 numerator = _usdToCopRate * 1e6;
            console.log("Numerator (_usdToCopRate * 1e6):", numerator);
            
            _vcopToCopRate = numerator / vcopToUsdPrice;
            console.log("VCOP/COP = numerator / vcopToUsdPrice =", _vcopToCopRate);
            
            // Show decimal value for verification
            uint256 integer = _vcopToCopRate / 1e6;
            uint256 fraction = _vcopToCopRate % 1e6;
            console.log("VCOP/COP as decimal:", integer, ".", fraction);
        }
        
        console.log("New calculated VCOP/COP rate:", _vcopToCopRate);
        if (address(priceCalculator) != address(0)) {
            console.log("Current tick:", currentTick);
        }
        
        // Verify parity
        bool isAtParity = isVcopAtParity();
        console.log("Is at 1:1 parity?:", isAtParity);
        console.log("======================================");
        
        emit VcopToCopRateUpdated(oldVcopToCopRate, _vcopToCopRate);
        
        return (_vcopToCopRate, vcopToUsdPrice);
    }

    /**
     * @dev Checks if VCOP price is at 1:1 parity with COP
     * @return true if price is within parity range
     */
    function isVcopAtParity() public view returns (bool) {
        // Show current VCOP/COP value being evaluated
        console.log("Checking parity with VCOP/COP =", _vcopToCopRate);
        
        if (address(priceCalculator) != address(0)) {
            bool parityFromCalculator = priceCalculator.isVcopAtParity();
            console.log("Parity according to calculator:", parityFromCalculator);
            return parityFromCalculator;
        }
        
        // Fallback implementation if no calculator
        // Uses the last value of _vcopToCopRate
        // 1e6 is the representation of 1 COP with 6 decimals
        // Consider 1% tolerance
        uint256 toleranceLower = 990000; // 0.99 * 1e6
        uint256 toleranceUpper = 1010000; // 1.01 * 1e6
        
        bool atParity = (_vcopToCopRate >= toleranceLower && _vcopToCopRate <= toleranceUpper);
        console.log("Lower tolerance:", toleranceLower);
        console.log("Upper tolerance:", toleranceUpper);
        console.log("Is at parity? (fallback):", atParity);
        
        return atParity;
    }

    /**
     * @dev Gets the USD to COP exchange rate
     * @return The rate in 6 decimal format (e.g., 4200e6 for 4200 COP per 1 USD)
     */
    function getUsdToCopRate() external returns (uint256) {
        console.log("USD/COP rate query by:", msg.sender);
        console.log("Current USD/COP rate:", _usdToCopRate);
        
        emit PriceRequested(msg.sender, "USD/COP");
        emit PriceProvided(msg.sender, "USD/COP", _usdToCopRate);
        
        return _usdToCopRate;
    }

    /**
     * @dev Gets the VCOP to COP exchange rate, first updating it from the pool
     * @return The rate in 6 decimal format (e.g., 1e6 for 1:1)
     */
    function getVcopToCopRate() external returns (uint256) {
        // Update rates from the pool before returning the value
        updateRatesFromPool();
        
        console.log("VCOP/COP rate query by:", msg.sender);
        console.log("Current VCOP/COP rate:", _vcopToCopRate);
        
        // Show value as decimal for verification
        uint256 integer = _vcopToCopRate / 1e6;
        uint256 fraction = _vcopToCopRate % 1e6;
        console.log("VCOP/COP value as decimal:", integer, ".", fraction);
        
        emit PriceRequested(msg.sender, "VCOP/COP");
        emit PriceProvided(msg.sender, "VCOP/COP", _vcopToCopRate);
        
        return _vcopToCopRate;
    }
    
    /**
     * @dev Gets the VCOP price in USD directly from the pool
     * @return The price in 6 decimal format
     */
    function getVcopToUsdPrice() external returns (uint256) {
        uint256 vcopToUsdPrice = getVcopToUsdPriceFromPool();
        
        console.log("VCOP/USD price query by:", msg.sender);
        console.log("Pool VCOP/USD price:", vcopToUsdPrice);
        
        emit PriceRequested(msg.sender, "VCOP/USD");
        emit PriceProvided(msg.sender, "VCOP/USD", vcopToUsdPrice);
        
        return vcopToUsdPrice;
    }
    
    /**
     * @dev Gets the VCOP price for the rebase mechanism
     * This method is maintained for compatibility with the existing rebase system
     * @return The price in 6 decimal format
     */
    function getPrice() external returns (uint256) {
        // Update rates from the pool before returning the value
        updateRatesFromPool();
        
        console.log("Price query for rebase by:", msg.sender);
        console.log("Updated VCOP/COP rate:", _vcopToCopRate);
        
        // Show value as decimal for verification
        uint256 integer = _vcopToCopRate / 1e6;
        uint256 fraction = _vcopToCopRate % 1e6;
        console.log("Rebase value as decimal:", integer, ".", fraction);
        
        emit PriceRequested(msg.sender, "REBASE");
        emit PriceProvided(msg.sender, "REBASE", _vcopToCopRate);
        
        return _vcopToCopRate;
    }

    /**
     * @dev Manually updates the USD to COP rate (owner only)
     * @param newRate The new rate to set (in 6 decimal format)
     */
    function setUsdToCopRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Rate must be greater than zero");
        
        uint256 oldRate = _usdToCopRate;
        _usdToCopRate = newRate;
        
        console.log("USD/COP rate updated by:", msg.sender);
        console.log("Previous rate:", oldRate);
        console.log("New rate:", newRate);
        
        emit UsdToCopRateUpdated(oldRate, newRate);
    }
} 