#!/usr/bin/env bun

import { privateKeyToAccount } from 'viem/accounts'
import { createWalletClient, createPublicClient, http, getContract, keccak256, encodePacked } from 'viem'
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

// Configuration
const privateKey = process.env.PRIVATE_KEY as `0x${string}`
if (!privateKey) {
  throw new Error('PRIVATE_KEY environment variable is required')
}

const contracts = getContracts()

const account = privateKeyToAccount(privateKey)

const publicClient = createPublicClient({
  chain: unichainSepolia,
  transport: http()
})

console.log('🔍 Pool Existence Check')
console.log('=======================')
console.log('Network: Unichain Sepolia')
console.log('Account:', account.address)
console.log()

// Pool configuration
const poolKey = {
  currency0: '0x7f7FD1D6A6BF6225F4872Fc8aa165E43Bf22D30c' as `0x${string}`, // VETH
  currency1: '0xb2feD1a40Fe6CA0be97Cde27e1D2dF1CC65Fd101' as `0x${string}`, // USDC
  fee: 3000,
  tickSpacing: 60,
  hooks: contracts.perpsHook.address as `0x${string}`
}

// Calculate PoolId manually (same as Uniswap V4)
function calculatePoolId(poolKey: any): `0x${string}` {
  const encoded = encodePacked(
    ['address', 'address', 'uint24', 'int24', 'address'],
    [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]
  )
  return keccak256(encoded)
}

const expectedPoolId = calculatePoolId(poolKey)

console.log('📋 Pool Configuration:')
console.log('Currency0 (VETH):', poolKey.currency0)
console.log('Currency1 (USDC):', poolKey.currency1)
console.log('Fee:', poolKey.fee)
console.log('Tick Spacing:', poolKey.tickSpacing)
console.log('Hooks:', poolKey.hooks)
console.log()
console.log('Expected PoolId:', expectedPoolId)
console.log()

async function checkPoolExists() {
  try {
    const poolManager = getContract({
      address: contracts.poolManager.address as `0x${string}`,
      abi: [
        {
          type: 'function',
          name: 'getSlot0',
          inputs: [{ name: 'poolId', type: 'bytes32' }],
          outputs: [
            { name: 'sqrtPriceX96', type: 'uint160' },
            { name: 'tick', type: 'int24' },
            { name: 'protocolFee', type: 'uint24' },
            { name: 'lpFee', type: 'uint24' }
          ],
          stateMutability: 'view'
        }
      ],
      client: { public: publicClient }
    })

    console.log('1. Checking if pool exists...')
    const slot0 = await poolManager.read.getSlot0([expectedPoolId])
    
    console.log('✅ Pool EXISTS!')
    console.log('Slot0 Data:')
    console.log('  sqrtPriceX96:', slot0[0].toString())
    console.log('  tick:', slot0[1].toString())
    console.log('  protocolFee:', slot0[2].toString())
    console.log('  lpFee:', slot0[3].toString())
    
    if (slot0[0] > 0) {
      console.log('  ✅ Pool is initialized (sqrtPriceX96 > 0)')
    } else {
      console.log('  ❌ Pool exists but not initialized (sqrtPriceX96 = 0)')
    }
    
  } catch (error: any) {
    if (error.message?.includes('not initialized') || error.message?.includes('PoolNotInitialized')) {
      console.log('❌ Pool does NOT exist or is not initialized')
    } else {
      console.log('❌ Error checking pool:', error.message || error)
    }
  }
}

checkPoolExists()
