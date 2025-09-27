// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @notice Interface for price oracles
interface IPriceOracle {
    function getPrice(address asset) external view returns (uint256 price, uint256 updatedAt);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice Interface for Pyth price updates
interface IPythPriceUpdate {
    function updatePythPrices(bytes[] calldata priceUpdateData) external payable;
    function getPythUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint256);
}

/// @notice Interface for vAMM hooks to get mark price
interface IVAMMHook {
    function getMarkPrice(PoolId poolId) external view returns (uint256);
    function getMarketState(PoolId poolId)
        external
        view
        returns (
            uint256 virtualBase,
            uint256 virtualQuote,
            uint256 k,
            int256 globalFundingIndex,
            uint256 totalLongOI,
            uint256 totalShortOI,
            uint256 maxOICap,
            uint256 lastFundingTime,
            address spotPriceFeed,
            bool isActive
        );
}

/// @title FundingOracle - Price Aggregation and Funding Rate Oracle
/// @notice Provides robust price data and funding rate calculations for perpetual futures
/// @dev Uses multiple price sources and median calculation for manipulation resistance
contract FundingOracle is Ownable {
    using PoolIdLibrary for PoolId;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Market price data for funding calculations
    struct MarketData {
        uint256 markPrice; // Current mark price (from multiple sources)
        uint256 spotPrice; // Spot price from external oracle
        int256 globalFundingIndex; // Cumulative funding index (1e18 precision)
        uint256 lastFundingUpdate; // Timestamp of last funding update
        uint256 fundingInterval; // How often funding is updated (seconds)
        int256 maxFundingRate; // Maximum funding rate per interval (1e18 precision)
        uint256 fundingRateFactor; // Funding rate sensitivity (k factor)
        bool isActive; // Market is active for funding
    }

    /// @notice Price source configuration
    struct PriceSource {
        address oracle; // Oracle contract address
        uint256 weight; // Weight in median calculation
        uint256 maxAge; // Maximum age for price data (seconds)
        bool isActive; // Source is active
        bytes32 pythPriceFeedId; // Pyth price feed ID (if using Pyth)
        bool isPythSource; // Whether this is a Pyth price source
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Market data by pool ID
    mapping(PoolId => MarketData) public markets;

    /// @notice External price sources for each market
    mapping(PoolId => PriceSource[]) public priceSources;

    /// @notice vAMM hook addresses for mark price calculation
    mapping(PoolId => address) public vammHooks;

    /// @notice Pyth contract instance
    IPyth public immutable pyth;

    /// @notice Price feed IDs for each market (for Pyth integration)
    mapping(PoolId => bytes32) public pythPriceFeedIds;

    /// @notice Maximum price staleness for Pyth feeds (seconds)
    uint256 public pythMaxStaleness = 60;

    /// @notice Default funding parameters
    uint256 public constant DEFAULT_FUNDING_INTERVAL = 1 hours;
    int256 public constant DEFAULT_MAX_FUNDING_RATE = 0.01e18; // 1% per interval
    uint256 public constant DEFAULT_FUNDING_RATE_FACTOR = 0.5e18; // 0.5 sensitivity

    /// @notice Price precision
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant FUNDING_PRECISION = 1e18;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketAdded(PoolId indexed poolId, address vammHook);
    event FundingUpdated(PoolId indexed poolId, int256 newFundingIndex, int256 fundingRate, uint256 timestamp);
    event PriceSourceAdded(PoolId indexed poolId, address oracle, uint256 weight);
    event PriceSourceUpdated(PoolId indexed poolId, address oracle, uint256 weight, bool isActive);
    event PythPriceFeedAdded(PoolId indexed poolId, bytes32 priceFeedId);
    event PythPricesUpdated(PoolId indexed poolId, uint256 price, uint256 timestamp);
    event MarkPriceUpdated(PoolId indexed poolId, uint256 markPrice, uint256 spotPrice, int256 premium);
    event MarketStatusChanged(PoolId indexed poolId, bool isActive);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error MarketNotFound();
    error MarketNotActive();
    error InvalidPriceSource();
    error StalePrice();
    error InsufficientPriceSources();
    error InvalidFundingParameters();
    error PythUpdateRequired();
    error InsufficientPythFee();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor
    /// @param pythContract Address of the Pyth contract
    constructor(address pythContract) Ownable(msg.sender) {
        require(pythContract != address(0), "Invalid Pyth contract");
        pyth = IPyth(pythContract);
    }

    /*//////////////////////////////////////////////////////////////
                          MARKET MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Add a new market for funding calculations
    /// @param poolId Pool identifier
    /// @param vammHook Address of the vAMM hook contract
    /// @param pythPriceFeedId Pyth price feed ID for this market (optional, use 0x0 if not using Pyth)
    function addMarket(PoolId poolId, address vammHook, bytes32 pythPriceFeedId) external onlyOwner {
        require(vammHook != address(0), "Invalid vAMM hook");

        vammHooks[poolId] = vammHook;
        
        if (pythPriceFeedId != bytes32(0)) {
            pythPriceFeedIds[poolId] = pythPriceFeedId;
            emit PythPriceFeedAdded(poolId, pythPriceFeedId);
        }

        markets[poolId] = MarketData({
            markPrice: 0,
            spotPrice: 0,
            globalFundingIndex: 0,
            lastFundingUpdate: block.timestamp,
            fundingInterval: DEFAULT_FUNDING_INTERVAL,
            maxFundingRate: DEFAULT_MAX_FUNDING_RATE,
            fundingRateFactor: DEFAULT_FUNDING_RATE_FACTOR,
            isActive: true
        });

        emit MarketAdded(poolId, vammHook);
    }

    /// @notice Add price source for a market
    /// @param poolId Pool identifier
    /// @param oracle Oracle contract address
    /// @param weight Weight in median calculation
    /// @param maxAge Maximum age for price data
    function addPriceSource(PoolId poolId, address oracle, uint256 weight, uint256 maxAge) external onlyOwner {
        if (markets[poolId].lastFundingUpdate == 0) revert MarketNotFound();
        require(oracle != address(0), "Invalid oracle");
        require(weight > 0, "Invalid weight");

        priceSources[poolId].push(PriceSource({
            oracle: oracle, 
            weight: weight, 
            maxAge: maxAge, 
            isActive: true,
            pythPriceFeedId: bytes32(0),
            isPythSource: false
        }));

        emit PriceSourceAdded(poolId, oracle, weight);
    }

    /// @notice Add Pyth price source for a market
    /// @param poolId Pool identifier
    /// @param pythPriceFeedId Pyth price feed ID
    /// @param weight Weight in median calculation
    /// @param maxAge Maximum age for price data
    function addPythPriceSource(PoolId poolId, bytes32 pythPriceFeedId, uint256 weight, uint256 maxAge) external onlyOwner {
        if (markets[poolId].lastFundingUpdate == 0) revert MarketNotFound();
        require(pythPriceFeedId != bytes32(0), "Invalid price feed ID");
        require(weight > 0, "Invalid weight");

        priceSources[poolId].push(PriceSource({
            oracle: address(pyth), 
            weight: weight, 
            maxAge: maxAge, 
            isActive: true,
            pythPriceFeedId: pythPriceFeedId,
            isPythSource: true
        }));

        emit PriceSourceAdded(poolId, address(pyth), weight);
    }

    /*//////////////////////////////////////////////////////////////
                         PYTH PRICE UPDATES
    //////////////////////////////////////////////////////////////*/

    /// @notice Update Pyth prices with price update data
    /// @param priceUpdateData Array of price update data from Pyth
    function updatePythPrices(bytes[] calldata priceUpdateData) external payable {
        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        if (msg.value < fee) revert InsufficientPythFee();
        
        pyth.updatePriceFeeds{value: fee}(priceUpdateData);
        
        // Refund excess payment
        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    /// @notice Get the fee required to update Pyth prices
    /// @param priceUpdateData Array of price update data
    /// @return fee Required fee in wei
    function getPythUpdateFee(bytes[] calldata priceUpdateData) external view returns (uint256 fee) {
        return pyth.getUpdateFee(priceUpdateData);
    }

    /// @notice Update funding with Pyth price updates
    /// @param poolId Pool identifier
    /// @param priceUpdateData Array of price update data from Pyth (optional, can be empty)
    function updateFundingWithPyth(PoolId poolId, bytes[] calldata priceUpdateData) external payable {
        MarketData storage market = markets[poolId];
        if (!market.isActive) revert MarketNotActive();

        // Update Pyth prices if provided
        if (priceUpdateData.length > 0) {
            uint256 fee = pyth.getUpdateFee(priceUpdateData);
            if (msg.value < fee) revert InsufficientPythFee();
            
            pyth.updatePriceFeeds{value: fee}(priceUpdateData);
            
            // Refund excess payment
            if (msg.value > fee) {
                payable(msg.sender).transfer(msg.value - fee);
            }
        }

        // Check if enough time has passed
        if (block.timestamp < market.lastFundingUpdate + market.fundingInterval) {
            return; // Too early to update
        }

        // Get current prices
        uint256 markPrice = getMarkPrice(poolId);
        uint256 spotPrice = getSpotPrice(poolId);

        // Calculate funding rate
        int256 fundingRate = _calculateFundingRate(poolId, markPrice, spotPrice);

        // Update global funding index
        market.globalFundingIndex += fundingRate;
        market.lastFundingUpdate = block.timestamp;
        market.markPrice = markPrice;
        market.spotPrice = spotPrice;

        emit FundingUpdated(poolId, market.globalFundingIndex, fundingRate, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                         FUNDING CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update funding for a market
    /// @param poolId Pool identifier
    function updateFunding(PoolId poolId) external {
        MarketData storage market = markets[poolId];
        if (!market.isActive) revert MarketNotActive();

        // Check if enough time has passed
        if (block.timestamp < market.lastFundingUpdate + market.fundingInterval) {
            return; // Too early to update
        }

        // Get current prices
        uint256 markPrice = getMarkPrice(poolId);
        uint256 spotPrice = getSpotPrice(poolId);

        // Calculate funding rate
        int256 fundingRate = _calculateFundingRate(poolId, markPrice, spotPrice);

        // Update global funding index
        market.globalFundingIndex += fundingRate;
        market.lastFundingUpdate = block.timestamp;
        market.markPrice = markPrice;
        market.spotPrice = spotPrice;

        emit FundingUpdated(poolId, market.globalFundingIndex, fundingRate, block.timestamp);
    }

    /// @notice Calculate funding rate based on premium
    /// @param poolId Pool identifier
    /// @param markPrice Current mark price
    /// @param spotPrice Current spot price
    /// @return Funding rate for this interval
    function _calculateFundingRate(PoolId poolId, uint256 markPrice, uint256 spotPrice)
        internal
        view
        returns (int256)
    {
        if (spotPrice == 0) return 0;

        MarketData storage market = markets[poolId];

        // Calculate premium: (mark - spot) / spot
        int256 premium = (int256(markPrice) - int256(spotPrice)) * int256(FUNDING_PRECISION) / int256(spotPrice);

        // Funding rate = k * premium (where k is the funding rate factor)
        int256 fundingRate = (premium * int256(market.fundingRateFactor)) / int256(FUNDING_PRECISION);

        // Apply maximum funding rate cap
        if (fundingRate > market.maxFundingRate) {
            fundingRate = market.maxFundingRate;
        } else if (fundingRate < -market.maxFundingRate) {
            fundingRate = -market.maxFundingRate;
        }

        return fundingRate;
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get mark price using multiple sources and median calculation
    /// @param poolId Pool identifier
    /// @return Mark price in 1e18 precision
    function getMarkPrice(PoolId poolId) public view returns (uint256) {
        address vammHook = vammHooks[poolId];
        if (vammHook == address(0)) revert MarketNotFound();

        // Get vAMM price
        uint256 vammPrice = IVAMMHook(vammHook).getMarkPrice(poolId);

        // Get external prices
        uint256[] memory prices = new uint256[](priceSources[poolId].length + 1);
        prices[0] = vammPrice;

        uint256 validPrices = 1;
        for (uint256 i = 0; i < priceSources[poolId].length; i++) {
            PriceSource storage source = priceSources[poolId][i];
            if (!source.isActive) continue;

            if (source.isPythSource) {
                // Handle Pyth price source
                try pyth.getPriceNoOlderThan(source.pythPriceFeedId, source.maxAge) returns (PythStructs.Price memory pythPrice) {
                    if (pythPrice.price > 0) {
                        // Convert Pyth price to 1e18 precision
                        uint256 price = _convertPythPrice(pythPrice);
                        prices[validPrices] = price;
                        validPrices++;
                    }
                } catch {
                    // Skip failed Pyth price
                    continue;
                }
            } else {
                // Handle traditional oracle
                try IPriceOracle(source.oracle).getPrice(address(0)) returns (uint256 price, uint256 updatedAt) {
                    if (block.timestamp - updatedAt <= source.maxAge && price > 0) {
                        prices[validPrices] = price;
                        validPrices++;
                    }
                } catch {
                    // Skip failed oracle
                    continue;
                }
            }
        }

        // Return median of valid prices
        return _calculateMedian(prices, validPrices);
    }

    /// @notice Get spot price from external oracles
    /// @param poolId Pool identifier
    /// @return Spot price in 1e18 precision
    function getSpotPrice(PoolId poolId) public view returns (uint256) {
        PriceSource[] storage sources = priceSources[poolId];
        if (sources.length == 0) {
            // If no external sources, use vAMM price as fallback
            return getMarkPrice(poolId);
        }

        uint256[] memory prices = new uint256[](sources.length);
        uint256 validPrices = 0;

        for (uint256 i = 0; i < sources.length; i++) {
            if (!sources[i].isActive) continue;

            if (sources[i].isPythSource) {
                // Handle Pyth price source
                try pyth.getPriceNoOlderThan(sources[i].pythPriceFeedId, sources[i].maxAge) returns (PythStructs.Price memory pythPrice) {
                    if (pythPrice.price > 0) {
                        uint256 price = _convertPythPrice(pythPrice);
                        prices[validPrices] = price;
                        validPrices++;
                    }
                } catch {
                    continue;
                }
            } else {
                // Handle traditional oracle
                try IPriceOracle(sources[i].oracle).getPrice(address(0)) returns (uint256 price, uint256 updatedAt) {
                    if (block.timestamp - updatedAt <= sources[i].maxAge && price > 0) {
                        prices[validPrices] = price;
                        validPrices++;
                    }
                } catch {
                    continue;
                }
            }
        }

        if (validPrices == 0) revert InsufficientPriceSources();

        return _calculateMedian(prices, validPrices);
    }

    /// @notice Get premium (mark - spot) in 1e18 precision
    /// @param poolId Pool identifier
    /// @return Premium as signed integer
    function premiumX18(PoolId poolId) external view returns (int256) {
        uint256 markPrice = getMarkPrice(poolId);
        uint256 spotPrice = getSpotPrice(poolId);

        return int256(markPrice) - int256(spotPrice);
    }

    /// @notice Calculate median of price array
    /// @param prices Array of prices
    /// @param length Number of valid prices
    /// @return Median price
    function _calculateMedian(uint256[] memory prices, uint256 length) internal pure returns (uint256) {
        if (length == 0) return 0;
        if (length == 1) return prices[0];

        // Simple bubble sort for small arrays
        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (prices[j] > prices[j + 1]) {
                    uint256 temp = prices[j];
                    prices[j] = prices[j + 1];
                    prices[j + 1] = temp;
                }
            }
        }

        // Return median
        if (length % 2 == 0) {
            return (prices[length / 2 - 1] + prices[length / 2]) / 2;
        } else {
            return prices[length / 2];
        }
    }

    /// @notice Convert Pyth price to 1e18 precision
    /// @param pythPrice Pyth price structure
    /// @return price Price in 1e18 precision
    function _convertPythPrice(PythStructs.Price memory pythPrice) internal pure returns (uint256) {
        if (pythPrice.price <= 0) return 0;
        
        uint256 price = uint256(uint64(pythPrice.price));
        int32 expo = pythPrice.expo;
        
        // Bound exponent to reasonable range to prevent overflow/underflow
        // Real Pyth feeds typically use exponents between -12 and +12
        if (expo > 18) expo = 18;   // Cap positive exponent
        if (expo < -18) expo = -18; // Cap negative exponent
        
        // For very small prices that would round to 0, return a minimum value
        if (expo < -12 && price < 1000) {
            return 1; // Minimum non-zero price
        }
        
        // Apply the exponent to get the actual price
        if (expo >= 0) {
            // Positive exponent: multiply by 10^expo
            price = price * (10 ** uint32(expo));
            // Scale to 1e18 precision
            return price * PRICE_PRECISION;
        } else {
            // Negative exponent: scale to 1e18 first, then divide to avoid precision loss
            uint256 divisor = 10 ** uint32(-expo);
            uint256 result = (price * PRICE_PRECISION) / divisor;
            
            // Ensure we don't return 0 for valid but small prices
            return result > 0 ? result : 1;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        PYTH UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get Pyth price for a specific feed ID
    /// @param priceFeedId Pyth price feed ID
    /// @return price Price in 1e18 precision
    /// @return publishTime When the price was published
    function getPythPrice(bytes32 priceFeedId) external view returns (uint256 price, uint256 publishTime) {
        PythStructs.Price memory pythPrice = pyth.getPriceNoOlderThan(priceFeedId, pythMaxStaleness);
        return (_convertPythPrice(pythPrice), pythPrice.publishTime);
    }

    /// @notice Get Pyth price for a market's primary feed
    /// @param poolId Pool identifier
    /// @return price Price in 1e18 precision
    /// @return publishTime When the price was published
    function getMarketPythPrice(PoolId poolId) external view returns (uint256 price, uint256 publishTime) {
        bytes32 priceFeedId = pythPriceFeedIds[poolId];
        if (priceFeedId == bytes32(0)) return (0, 0);
        
        PythStructs.Price memory pythPrice = pyth.getPriceNoOlderThan(priceFeedId, pythMaxStaleness);
        return (_convertPythPrice(pythPrice), pythPrice.publishTime);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get market data
    /// @param poolId Pool identifier
    /// @return Market data struct
    function getMarketData(PoolId poolId) external view returns (MarketData memory) {
        return markets[poolId];
    }

    /// @notice Get current funding index
    /// @param poolId Pool identifier
    /// @return Current global funding index
    function getFundingIndex(PoolId poolId) external view returns (int256) {
        return markets[poolId].globalFundingIndex;
    }

    /// @notice Check if funding update is needed
    /// @param poolId Pool identifier
    /// @return True if update is needed
    function needsFundingUpdate(PoolId poolId) external view returns (bool) {
        MarketData storage market = markets[poolId];
        return block.timestamp >= market.lastFundingUpdate + market.fundingInterval;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update market status
    /// @param poolId Pool identifier
    /// @param isActive New status
    function setMarketStatus(PoolId poolId, bool isActive) external onlyOwner {
        markets[poolId].isActive = isActive;
        emit MarketStatusChanged(poolId, isActive);
    }

    /// @notice Update funding parameters
    /// @param poolId Pool identifier
    /// @param fundingInterval New funding interval
    /// @param maxFundingRate New maximum funding rate
    /// @param fundingRateFactor New funding rate factor
    function updateFundingParameters(
        PoolId poolId,
        uint256 fundingInterval,
        int256 maxFundingRate,
        uint256 fundingRateFactor
    ) external onlyOwner {
        if (fundingInterval == 0 || maxFundingRate <= 0 || fundingRateFactor == 0) {
            revert InvalidFundingParameters();
        }

        MarketData storage market = markets[poolId];
        market.fundingInterval = fundingInterval;
        market.maxFundingRate = maxFundingRate;
        market.fundingRateFactor = fundingRateFactor;
    }

    /// @notice Update price source configuration
    /// @param poolId Pool identifier
    /// @param sourceIndex Index of price source
    /// @param weight New weight
    /// @param isActive New active status
    function updatePriceSource(PoolId poolId, uint256 sourceIndex, uint256 weight, bool isActive) external onlyOwner {
        require(sourceIndex < priceSources[poolId].length, "Invalid source index");

        PriceSource storage source = priceSources[poolId][sourceIndex];
        source.weight = weight;
        source.isActive = isActive;

        emit PriceSourceUpdated(poolId, source.oracle, weight, isActive);
    }

    /// @notice Set Pyth price feed ID for a market
    /// @param poolId Pool identifier
    /// @param priceFeedId Pyth price feed ID
    function setPythPriceFeedId(PoolId poolId, bytes32 priceFeedId) external onlyOwner {
        if (markets[poolId].lastFundingUpdate == 0) revert MarketNotFound();
        
        pythPriceFeedIds[poolId] = priceFeedId;
        emit PythPriceFeedAdded(poolId, priceFeedId);
    }

    /// @notice Set maximum staleness for Pyth prices
    /// @param maxStaleness Maximum staleness in seconds
    function setPythMaxStaleness(uint256 maxStaleness) external onlyOwner {
        require(maxStaleness > 0, "Invalid staleness");
        pythMaxStaleness = maxStaleness;
    }

    /// @notice Withdraw accumulated fees from Pyth updates
    /// @param to Address to send fees to
    function withdrawFees(address payable to) external onlyOwner {
        require(to != address(0), "Invalid address");
        to.transfer(address(this).balance);
    }

    /// @notice Check if market has Pyth integration
    /// @param poolId Pool identifier
    /// @return True if market has Pyth price feed ID set
    function hasMarketPythIntegration(PoolId poolId) external view returns (bool) {
        return pythPriceFeedIds[poolId] != bytes32(0);
    }

    /// @notice Get all price sources for a market
    /// @param poolId Pool identifier
    /// @return Array of price sources
    function getMarketPriceSources(PoolId poolId) external view returns (PriceSource[] memory) {
        return priceSources[poolId];
    }

    /// @notice Receive function to accept ETH for Pyth fee payments
    receive() external payable {
        // Accept ETH for Pyth update fees
    }
}
