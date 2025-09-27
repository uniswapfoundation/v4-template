#!/usr/bin/env bun

import { privateKeyToAccount } from 'viem/accounts'
import { createWalletClient, createPublicClient, http, getContract, parseEther, encodeFunctionData } from 'viem'
import { getContracts } from './contracts'

// Define Unichain Sepolia chain
const unichainSepolia = {
  id: 1301,
  name: 'Unichain Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://sepolia.unichain.org'] }
  },
  blockExplorers: {
    default: { name: 'Unichain Explorer', url: 'https://sepolia.uniscan.xyz' }
  },
  testnet: true
} as const

const contracts = getContracts()

// Configuration
const privateKey = process.env.PRIVATE_KEY as `0x${string}`
if (!privateKey) {
  throw new Error('PRIVATE_KEY environment variable is required')
}

const account = privateKeyToAccount(privateKey)

const publicClient = createPublicClient({
  chain: unichainSepolia,
  transport: http()
})

const walletClient = createWalletClient({
  account,
  chain: unichainSepolia,
  transport: http()
})

console.log('🧪 Testing Basic Pool Creation')
console.log('=======================')
console.log('Network: Unichain Sepolia')
console.log('Account:', account.address)
console.log()

// Test without hooks first
const poolKey = {
  currency0: '0x7f7FD1D6A6BF6225F4872Fc8aa165E43Bf22D30c' as `0x${string}`, // VETH
  currency1: '0xb2feD1a40Fe6CA0be97Cde27e1D2dF1CC65Fd101' as `0x${string}`, // USDC
  fee: 3000,
  tickSpacing: 60,
  hooks: '0x0000000000000000000000000000000000000000' as `0x${string}` // No hooks for basic test
}

const sqrtPriceX96 = BigInt("79228162514264337593543950336") // 1:1 price ratio

console.log('📋 Testing Basic Pool (No Hooks):')
console.log('Currency0 (VETH):', poolKey.currency0)
console.log('Currency1 (USDC):', poolKey.currency1)
console.log('Fee:', poolKey.fee)
console.log('Tick Spacing:', poolKey.tickSpacing)
console.log('Hooks:', poolKey.hooks)
console.log()

async function testBasicPool() {
  try {
    const poolManager = getContract({
      address: contracts.poolManager.address as `0x${string}`,
      abi: [
        {
          type: 'function',
          name: 'initialize',
          inputs: [
            {
              name: 'key',
              type: 'tuple',
              components: [
                { name: 'currency0', type: 'address' },
                { name: 'currency1', type: 'address' },
                { name: 'fee', type: 'uint24' },
                { name: 'tickSpacing', type: 'int24' },
                { name: 'hooks', type: 'address' }
              ]
            },
            { name: 'sqrtPriceX96', type: 'uint160' }
          ],
          outputs: [{ name: '', type: 'int24' }],
          stateMutability: 'payable'
        }
      ],
      client: { public: publicClient, wallet: walletClient }
    })

    console.log('1. Initializing basic pool (no hooks)...')
    const txHash = await poolManager.write.initialize([poolKey, sqrtPriceX96])
    
    console.log('✅ Pool initialized successfully!')
    console.log('Transaction Hash:', txHash)
    
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash })
    console.log('Gas Used:', receipt.gasUsed.toString())
    
  } catch (error) {
    console.error('❌ Error creating basic pool:', error)
  }
}

testBasicPool()
