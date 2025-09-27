// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MockOracle
 * @notice A simple mock oracle for testing purposes that provides price feeds
 */
contract MockOracle {
    mapping(address => uint256) private prices;
    mapping(address => uint256) private lastUpdated;
    
    uint8 public constant decimals = 18;
    string public description;
    
    event PriceUpdated(address indexed asset, uint256 price, uint256 timestamp);
    
    constructor(string memory _description) {
        description = _description;
    }
    
    /**
     * @notice Set the price for a specific asset
     * @param asset The asset address
     * @param price The price in 18 decimals
     */
    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
        lastUpdated[asset] = block.timestamp;
        emit PriceUpdated(asset, price, block.timestamp);
    }
    
    /**
     * @notice Get the latest price for an asset
     * @param asset The asset address
     * @return price The price in 18 decimals
     */
    function getPrice(address asset) external view returns (uint256 price) {
        price = prices[asset];
        require(price > 0, "MockOracle: Price not set");
        return price;
    }
    
    /**
     * @notice Get the latest round data (Chainlink compatible)
     * @return roundId The round ID (always 1 for mock)
     * @return answer The price
     * @return startedAt Started timestamp
     * @return updatedAt Updated timestamp  
     * @return answeredInRound Answered in round (always 1 for mock)
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // Return ETH price by default (you can extend this for multiple assets)
        uint256 ethPrice = prices[address(0)]; // Use address(0) for ETH
        require(ethPrice > 0, "MockOracle: ETH price not set");
        
        return (
            1, // roundId
            int256(ethPrice),
            lastUpdated[address(0)], // startedAt
            lastUpdated[address(0)], // updatedAt
            1 // answeredInRound
        );
    }
    
    /**
     * @notice Get the timestamp of the last update for an asset
     * @param asset The asset address
     * @return timestamp The last update timestamp
     */
    function getLastUpdated(address asset) external view returns (uint256 timestamp) {
        return lastUpdated[asset];
    }
}
