//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title PositionManagerAddresses
/// @notice Library containing Position Manager addresses for different chains
library PositionManagerAddresses {
    function getPositionManagerByChainId(uint256 chainId) internal pure returns (address) {
        //Ethereum
        if (chainId == 1) {
            return address(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
        } 
        //Unichain
        else if (chainId == 130) {
            return address(0x4529A01c7A0410167c5740C487A8DE60232617bf);
        } 
        //Optimism
        else if (chainId == 10) {
            return address(0x3C3Ea4B57a46241e54610e5f022E5c45859A1017);
        } 
        //Base
        else if (chainId == 8453) {
            return address(0x7C5f5A4bBd8fD63184577525326123B519429bDc);
        } 
        //Arbitrum One
        else if (chainId == 42161) {
            return address(0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869);
        } 
        //Polygon
        else if (chainId == 137) {
            return address(0x1Ec2eBf4F37E7363FDfe3551602425af0B3ceef9);
        } 
        //Blast
        else if (chainId == 81457) {
            return address(0x4AD2F4CcA2682cBB5B950d660dD458a1D3f1bAaD);
        } 
        //Zora
        else if (chainId == 7777777) {
            return address(0xf66C7b99e2040f0D9b326B3b7c152E9663543D63);
        } 
        //Worldchain
        else if (chainId == 480) {
            return address(0xC585E0f504613b5fBf874F21Af14c65260fB41fA);
        } 
        //Ink
        else if (chainId == 57073) {
            return address(0x1b35d13a2E2528f192637F14B05f0Dc0e7dEB566);
        } 
        //Soneium
        else if (chainId == 1868) {
            return address(0x1b35d13a2E2528f192637F14B05f0Dc0e7dEB566);
        } 
        //Avalanche
        else if (chainId == 43114) {
            return address(0xB74b1F14d2754AcfcbBe1a221023a5cf50Ab8ACD);
        } 
        //BNB Smart Chain
        else if (chainId == 56) {
            return address(0x7A4a5c919aE2541AeD11041A1AEeE68f1287f95b);
        } 
        //Unichain Sepolia
        else if (chainId == 1301) {
            return address(0xf969Aee60879C54bAAed9F3eD26147Db216Fd664);
        } 
        //Sepolia
        else if (chainId == 11155111) {
            return address(0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4);
        } 
        //Base Sepolia
        else if (chainId == 84532) {
            return address(0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80);
        } 
        //Arbitrum Sepolia
        else if (chainId == 421614) {
            return address(0xAc631556d3d4019C95769033B5E719dD77124BAc);
        } 
        //interop-alpha-0
        else if (chainId == 420120000) {
            return address(0x4498FE0b1DF6B476453440664A16E269B7587D0F);
        } 
        // interop-alpha-1
        else if (chainId == 420120001) {
            return address(0x4498FE0b1DF6B476453440664A16E269B7587D0F);
        } 
        
        else {
            revert("Unsupported chainId");
        }
    }
}