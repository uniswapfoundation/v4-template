import { createPublicClient, http, keccak256, toHex } from 'viem';
import { unichainSepolia } from 'viem/chains';
import { externalContracts } from './contracts';

const RPC_URL = "https://sepolia.unichain.org";
const CHAIN_ID = 1301;

const publicClient = createPublicClient({
  chain: unichainSepolia,
  transport: http(RPC_URL),
});

const contracts = externalContracts[CHAIN_ID];
if (!contracts) {
  throw new Error(`No contracts found for chain ID ${CHAIN_ID}`);
}

async function checkOwnership() {
  console.log("🔍 Checking Contract Ownership");
  console.log("==============================");
  
  try {
    // Check PositionManager owner
    const positionManagerOwner = await publicClient.readContract({
      address: contracts.positionManager.address as `0x${string}`,
      abi: contracts.positionManager.abi,
      functionName: 'owner',
    });
    console.log("PositionManager Owner:", positionManagerOwner);
    
    // Check MarketManager owner
    const marketManagerOwner = await publicClient.readContract({
      address: contracts.marketManager.address as `0x${string}`,
      abi: contracts.marketManager.abi,
      functionName: 'owner',
    });
    console.log("MarketManager Owner:", marketManagerOwner);
    
    // Check if we're a key manager for MarketManager
    const isKeyManager = await publicClient.readContract({
      address: contracts.marketManager.address as `0x${string}`,
      abi: contracts.marketManager.abi,
      functionName: 'keyManagers',
      args: ["0xcFE743EA353d4d3D2c20C41C7d878B2cbA66DA0a"],
    });
    console.log("Is Key Manager for MarketManager:", isKeyManager);
    
  } catch (error) {
    console.error("Error checking ownership:", error);
  }
}

checkOwnership();
