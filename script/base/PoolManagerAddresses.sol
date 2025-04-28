//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title PoolManagerAddresses
/// @notice Library containing Pool Manager addresses for different chains
library PoolManagerAddresses {
    function getPoolManagerByChainId(uint256 chainId) internal pure returns (address) {
        //Ethereum
        if (chainId == 1) {
            return address(0x000000000004444c5dc75cB358380D2e3dE08A90);
        } 
        //Unichain
        else if (chainId == 130) {
            return address(0x1F98400000000000000000000000000000000004);
        } 
        //Optimism
        else if (chainId == 10) {
            return address(0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3);
        } 
        //Base
        else if (chainId == 8453) {
            return address(0x498581fF718922c3f8e6A244956aF099B2652b2b);
        } 
        //Arbitrum One
        else if (chainId == 42161) {
            return address(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
        } 
        //Polygon
        else if (chainId == 137) {
            return address(0x67366782805870060151383F4BbFF9daB53e5cD6);
        } 
        //Blast
        else if (chainId == 81457) {
            return address(0x1631559198A9e474033433b2958daBC135ab6446);
        } 
        //Zora
        else if (chainId == 7777777) {
            return address(0x0575338e4C17006aE181B47900A84404247CA30f);
        } 
        //Worldchain
        else if (chainId == 480) {
            return address(0xb1860D529182ac3BC1F51Fa2ABd56662b7D13f33);
        } 
        //Ink
        else if (chainId == 57073) {
            return address(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
        } 
        //Soneium
        else if (chainId == 1868) {
            return address(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
        } 
        //Avalanche
        else if (chainId == 43114) {
            return address(0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32);
        } 
        //BNB Smart Chain
        else if (chainId == 56) {
            return address(0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF);
        } 
        //Unichain Sepolia
        else if (chainId == 1301) {
            return address(0x00B036B58a818B1BC34d502D3fE730Db729e62AC);
        } 
        //Sepolia
        else if (chainId == 11155111) {
            return address(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
        } 
        //Base Sepolia
        else if (chainId == 84532) {
            return address(0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408);
        } 
        //Arbitrum Sepolia
        else if (chainId == 421614) {
            return address(0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317);
        } 
        //interop-alpha-0
        else if (chainId == 420120000) {
            return address(0x9131B9084E6017Be19c6a0ef23f73dbB1Bf41f96);
        } 
        // interop-alpha-1
        else if (chainId == 420120001) {
            return address(0x9131B9084E6017Be19c6a0ef23f73dbB1Bf41f96);
        } 
        
        else {
            revert("Unsupported chainId");
        }
    }
}