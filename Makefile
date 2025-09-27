.PHONY: build install test clean deploy-hook create-pool add-liquidity swap start-anvil deploy-all

# Default values - can be overridden by environment variables
PRIVATE_KEY ?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
RPC_URL ?= http://localhost:8545
DEPLOYMENTS_FILE = deployments.json
ETHERSCAN_API_KEY ?= 

# Build and install dependencies
build:
	@echo "Installing dependencies and building contracts..."
	forge install --shallow
	forge build

install: build

# Testing
test-position-manager:
	@echo "Running PositionManager tests..."
	forge test --match-contract PositionManagerTest -vvv

test-perps-hook:
	@echo "Running PerpsHook tests..."
	forge test --match-contract PerpsHookTest -vvv

test-perps-hook-proper:
	@echo "Running PerpsHook proper tests..."
	forge test --match-contract PerpsHookProperTest -vv

# Production deployment targets
deploy-production-anvil:
	@echo "Deploying to local Anvil..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	forge script script/DeployProduction.s.sol:DeployProductionScript \
	--rpc-url http://localhost:8545 \
	--private-key $$PRIVATE_KEY \
	--broadcast

deploy-production-miner-anvil:
	@echo "Deploying to local Anvil with HookMiner..."
	forge script script/DeployProductionWithMiner.s.sol:DeployProductionWithMinerScript \
	--rpc-url http://localhost:8545 \
	--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
	--broadcast

deploy-production-miner-sepolia:
	@echo "Deploying to Sepolia testnet with HookMiner..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	DEPLOYMENT_NETWORK=sepolia forge script script/DeployProductionWithMiner.s.sol:DeployProductionWithMinerScript \
	--rpc-url $$SEPOLIA_RPC_URL \
	--private-key $$PRIVATE_KEY \
	--broadcast \
	--verify \
	--etherscan-api-key $$ETHERSCAN_API_KEY

deploy-production-miner-arbitrum-sepolia:
	@echo "Deploying to Arbitrum Sepolia testnet with HookMiner..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	DEPLOYMENT_NETWORK=arbitrum-sepolia forge script script/DeployProductionWithMiner.s.sol:DeployProductionWithMinerScript \
	--rpc-url $$ARBITRUM_SEPOLIA_RPC_URL \
	--private-key $$PRIVATE_KEY \
	--broadcast \
	--verify \
	--etherscan-api-key $$ARBISCAN_API_KEY

deploy-production-miner-unichain-sepolia:
	@echo "Deploying to Unichain Sepolia testnet with HookMiner..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	DEPLOYMENT_NETWORK=unichain-sepolia forge script script/DeployProductionWithMiner.s.sol:DeployProductionWithMinerScript \
	--rpc-url $$UNICHAIN_SEPOLIA_RPC_URL \
	--private-key $$PRIVATE_KEY \
	--broadcast

# Pool setup and testing on Unichain Sepolia
setup-pool-unichain-sepolia:
	@echo "Setting up liquidity pool on Unichain Sepolia..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	DEPLOYMENT_NETWORK=unichain-sepolia forge script script/UnichainPoolSetup.s.sol:UnichainPoolSetupScript \
	--rpc-url $$UNICHAIN_SEPOLIA_RPC_URL \
	--private-key $$PRIVATE_KEY \
	--gas-limit 50000000 \
	--gas-price 1000000000 \
	--broadcast \
	-vvv

# Simulate pool setup (no broadcast)
simulate-pool-unichain-sepolia:
	@echo "Simulating pool setup on Unichain Sepolia..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	DEPLOYMENT_NETWORK=unichain-sepolia forge script script/UnichainPoolSetup.s.sol:UnichainPoolSetupScript \
	--rpc-url $$UNICHAIN_SEPOLIA_RPC_URL \
	--private-key $$PRIVATE_KEY \
	-vvv

# Open perpetual positions on Unichain Sepolia
open-position-unichain-sepolia:
	@echo "Opening perpetual positions on Unichain Sepolia..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	DEPLOYMENT_NETWORK=unichain-sepolia forge script script/OpenPosition.s.sol:OpenPositionScript \
	--rpc-url $$UNICHAIN_SEPOLIA_RPC_URL \
	--private-key $$PRIVATE_KEY \
	--gas-limit 30000000 \
	--gas-price 1000000000 \
	--broadcast \
	-vvv

# Simulate opening positions (no broadcast)
simulate-open-position-unichain-sepolia:
	@echo "Simulating opening positions on Unichain Sepolia..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	DEPLOYMENT_NETWORK=unichain-sepolia forge script script/OpenPosition.s.sol:OpenPositionScript \
	--rpc-url $$UNICHAIN_SEPOLIA_RPC_URL \
	--private-key $$PRIVATE_KEY \
	-vvv

deploy-production-miner-mainnet:
	@echo "🚨 WARNING: Deploying to MAINNET with HookMiner 🚨"
	@echo "This will deploy contracts with real ETH. Are you sure? [y/N]"
	@read answer && [ "$$answer" = "y" ] || [ "$$answer" = "Y" ] || exit 1
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	DEPLOYMENT_NETWORK=mainnet forge script script/DeployProductionWithMiner.s.sol:DeployProductionWithMinerScript \
	--rpc-url $$MAINNET_RPC_URL \
	--private-key $$PRIVATE_KEY \
	--broadcast \
	--verify \
	--etherscan-api-key $$ETHERSCAN_API_KEY

deploy-production-sepolia:
	@echo "Deploying to Sepolia testnet..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	forge script script/DeployProduction.s.sol:DeployProductionScript \
	--rpc-url $$SEPOLIA_RPC_URL \
	--private-key $$PRIVATE_KEY \
	--broadcast \
	--verify \
	--etherscan-api-key $$ETHERSCAN_API_KEY

deploy-production-mainnet:
	@echo "🚨 WARNING: Deploying to MAINNET 🚨"
	@echo "This will deploy contracts with real ETH. Are you sure? [y/N]"
	@read answer && [ "$$answer" = "y" ] || [ "$$answer" = "Y" ] || exit 1
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	forge script script/DeployProduction.s.sol:DeployProductionScript \
	--rpc-url $$MAINNET_RPC_URL \
	--private-key $$PRIVATE_KEY \
	--broadcast \
	--verify \
	--etherscan-api-key $$ETHERSCAN_API_KEY

deploy-production-arbitrum:
	@echo "Deploying to Arbitrum..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	forge script script/DeployProduction.s.sol:DeployProductionScript \
	--rpc-url $$ARBITRUM_RPC_URL \
	--private-key $$PRIVATE_KEY \
	--broadcast \
	--verify \
	--etherscan-api-key $$ARBISCAN_API_KEY

verify-deployment:
	@echo "Verifying deployment integrity..."
	@if [ ! -f .env ]; then echo "Error: .env file not found. Copy .env.example to .env and configure it."; exit 1; fi
	@set -a && source .env && set +a && \
	forge script script/DeployProduction.s.sol:DeployProductionScript \
	--sig "verifyDeployment()" \
	--rpc-url http://localhost:8545

# Quick deployment setup
setup-deployment:
	@echo "Setting up deployment environment..."
	@if [ ! -f .env ]; then cp .env.example .env && echo "Created .env file from template. Please edit it with your configuration."; fi
	@echo "✓ Environment file ready"
	@echo "Next steps:"
	@echo "1. Edit .env with your private key and network settings"
	@echo "2. Run 'make deploy-production-anvil' for local testing"
	@echo "3. Run 'make deploy-production-sepolia' for testnet deployment"

# Integration testing
test-integration:
	@echo "Running integration test..."
	forge script script/QuickIntegrationTest.s.sol:QuickIntegrationTestScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvv

# ===================== TS / viem example scripts =====================
examples-deposit-margin:
	@echo "Depositing margin via viem script..."
	RPC_URL=$(RPC_URL) PRIVATE_KEY=$(PRIVATE_KEY) bun run examples/depositMargin.ts 1000

examples-open-long:
	@echo "Opening long position via viem script..."
	RPC_URL=$(RPC_URL) PRIVATE_KEY=$(PRIVATE_KEY) bun run examples/openLong.ts 1000

examples-open-short:
	@echo "Opening short position via viem script..."
	RPC_URL=$(RPC_URL) PRIVATE_KEY=$(PRIVATE_KEY) bun run examples/openShort.ts 500

examples-get-position:
	@if [ -z "$(TOKEN_ID)" ]; then echo "TOKEN_ID env var required: make examples-get-position TOKEN_ID=1"; exit 1; fi
	RPC_URL=$(RPC_URL) PRIVATE_KEY=$(PRIVATE_KEY) bun run examples/getPosition.ts $(TOKEN_ID)

examples-get-mark-price:
	@echo "Fetching mark price (supply POOL_ID optional)" 
	RPC_URL=$(RPC_URL) PRIVATE_KEY=$(PRIVATE_KEY) bun run examples/getMarkPrice.ts $(POOL_ID)

examples-withdraw-margin:
	@echo "Withdrawing margin via viem script..."
	@if [ -z "$(AMOUNT)" ]; then echo "AMOUNT env var required: make examples-withdraw-margin AMOUNT=500"; exit 1; fi
	RPC_URL=$(RPC_URL) PRIVATE_KEY=$(PRIVATE_KEY) bun run examples/withdrawMargin.ts $(AMOUNT)

examples-close-position:
	@echo "Closing position via viem script..."
	@if [ -z "$(TOKEN_ID)" ]; then echo "TOKEN_ID env var required: make examples-close-position TOKEN_ID=1"; exit 1; fi
	RPC_URL=$(RPC_URL) PRIVATE_KEY=$(PRIVATE_KEY) bun run examples/closePosition.ts $(TOKEN_ID)

test-integration-full:
	@echo "Running full integration flow test..."
	forge script script/TestIntegratedFlow.s.sol:TestIntegratedFlowScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvv

test:
	@echo "Running tests..."
	forge test

test-verbose:
	@echo "Running tests with verbose output..."
	forge test -vvv

test-gas:
	@echo "Running tests with gas reporting..."
	forge test --gas-report

# Local development
start-anvil:
	@echo "Starting Anvil local blockchain..."
	anvil --host 0.0.0.0

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	forge clean
	rm -rf out/ cache/ $(DEPLOYMENTS_FILE)

# Create .env file template
create-env:
	@echo "Creating .env file template..."
	@echo "PRIVATE_KEY=$(PRIVATE_KEY)" > .env
	@echo "RPC_URL=$(RPC_URL)" >> .env
	@echo "ETHERSCAN_API_KEY=" >> .env
	@echo ".env file created with default values"

# Deployment scripts
deploy-tokens:
	@echo "Deploying MockUSDC and MockVETH tokens..."
	forge script script/base/DeployToken.s.sol:DeployTokenScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv
	@echo "Token deployment completed"

deploy-tokens-verify:
	@echo "Deploying MockUSDC and MockVETH tokens with verification..."
	forge script script/base/DeployToken.s.sol:DeployTokenScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		-vvvv

deploy-usdc:
	@echo "Deploying MockUSDC token..."
	forge script script/DeployMockUSDC.s.sol:DeployMockUSDCScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

deploy-veth:
	@echo "Deploying MockVETH token..."
	forge script script/DeployMockVETH.s.sol:DeployMockVETHScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

mint-tokens:
	@echo "Minting tokens to recipients..."
	@echo "WARNING: Make sure to update token addresses in MintTokens.s.sol"
	forge script script/MintTokens.s.sol:MintTokensScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv
	@echo "Minting tokens to recipients..."
	@echo "⚠️  Make sure to update token addresses in MintTokens.s.sol"
	forge script script/MintTokens.s.sol:MintTokensScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

deploy-position-manager:
	@echo "Deploying PositionManager contract..."
	@echo "WARNING: Make sure to update USDC_ADDRESS in DeployPositionManager.s.sol"
	forge script script/DeployPositionManager.s.sol:DeployPositionManagerScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

deploy-position-manager-verify:
	@echo "Deploying PositionManager contract with verification..."
	@echo "WARNING: Make sure to update USDC_ADDRESS in DeployPositionManager.s.sol"
	forge script script/DeployPositionManager.s.sol:DeployPositionManagerScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		-vvvv

setup-markets:
	@echo "Setting up markets in PositionManager..."
	@echo "WARNING: Make sure to update addresses in SetupMarkets.s.sol"
	forge script script/SetupMarkets.s.sol:SetupMarketsScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

deploy-hook:
	@echo "Deploying Hook contract..."
	forge script script/00_DeployHook.s.sol:DeployHookScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		-vvvv
	@echo "Hook deployment completed"

deploy-perps-hook:
	@echo "Deploying PerpsHook contract..."
	forge script script/DeployPerpsHook.s.sol:DeployPerpsHookScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

# New contract deployments
deploy-margin-account:
	@echo "Deploying MarginAccount..."
	forge script script/DeployMarginAccount.s.sol:DeployMarginAccountScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

deploy-insurance-fund:
	@echo "Deploying InsuranceFund..."
	forge script script/DeployInsuranceFund.s.sol:DeployInsuranceFundScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

deploy-funding-oracle:
	@echo "Deploying FundingOracle..."
	forge script script/DeployFundingOracle.s.sol:DeployFundingOracleScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

# Deploy all new contracts and set up authorizations
deploy-new-contracts:
	@echo "Deploying all new contracts (MarginAccount, InsuranceFund, FundingOracle, PerpsRouter)..."
	forge script script/DeployAllNew.s.sol:DeployAllNewScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

# Deploy integrated system (recommended approach)
deploy-integrated-system:
	@echo "Deploying integrated perpetual futures system..."
	forge script script/DeployIntegratedSystem.s.sol:DeployIntegratedSystemScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

# Deploy integrated PerpsHook with proper v4 address
deploy-perps-hook-integrated:
	@echo "Deploying integrated PerpsHook with MarginAccount support..."
	forge script script/DeployPerpsHook.s.sol:DeployPerpsHookScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

# Deploy LiquidationEngine
deploy-liquidation-engine:
	@echo "Deploying LiquidationEngine..."
	@echo "NOTE: Update contract addresses in the deployment script first"
	@echo "LiquidationEngine.sol is ready but needs a deployment script"

deploy-hook-local:
	@echo "Deploying Hook contract to local anvil..."
	forge script script/00_DeployHook.s.sol:DeployHookScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

create-pool:
	@echo "Creating pool and adding initial liquidity..."
	forge script script/01_CreatePoolAndAddLiquidity.s.sol:CreatePoolAndAddLiquidityScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

add-liquidity:
	@echo "Adding liquidity to existing pool..."
	forge script script/02_AddLiquidity.s.sol:AddLiquidityScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

swap:
	@echo "Executing swap..."
	forge script script/03_Swap.s.sol:SwapScript \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

# Complete integrated deployment flow (RECOMMENDED)
deploy-all-integrated: build deploy-tokens deploy-integrated-system test-integration
	@echo "Complete integrated deployment finished!"
	@echo "✓ All contracts deployed with full integration"
	@echo "✓ MarginAccount centralized USDC management"
	@echo "✓ PerpsHook integrated with MarginAccount"
	@echo "✓ FundingOracle configured with ETH-USDC market"
	@echo "✓ Integration test passed"
	@echo ""
	@echo "Deployed contracts:"
	@echo "  MarginAccount, InsuranceFund, PositionManager (integrated),"
	@echo "  FundingOracle, PerpsHook (integrated), PerpsRouter"

# Legacy deployment flow
deploy-all-local: build deploy-tokens deploy-position-manager deploy-hook-local setup-markets create-pool
	@echo "Legacy local deployment finished!"
	@echo "NOTE: Use 'make deploy-all-integrated' for the new integrated system"

# Production deployment (requires verification)
deploy-all-mainnet: build deploy-tokens-verify deploy-position-manager-verify deploy-hook setup-markets create-pool
	@echo "Complete mainnet deployment finished!"
	@echo "Tokens deployed, PositionManager deployed, hook deployed, markets setup, pool created, and initial liquidity added"

# Development workflow
dev-setup: clean build create-env
	@echo "Development environment setup complete!"
	@echo "1. Start anvil: make start-anvil"
	@echo "2. Deploy contracts: make deploy-all-local"
	@echo "3. Test swaps: make swap"

# Quick integrated development cycle (RECOMMENDED)
quick-deploy-integrated: build deploy-tokens deploy-integrated-system test-integration
	@echo "Quick integrated deployment and test cycle completed!"
	@echo "Ready for perpetual futures trading!"

# Legacy quick development cycle  
quick-deploy: build deploy-tokens deploy-position-manager deploy-hook-local setup-markets create-pool swap
	@echo "Legacy quick deployment completed!"
	@echo "NOTE: Use 'make quick-deploy-integrated' for the new integrated system"

# Utility commands
check-balance:
	@echo "Checking ETH balance..."
	@if [ -z "$(ADDRESS)" ]; then \
		echo "Usage: make check-balance ADDRESS=0x..."; \
	else \
		cast balance $(ADDRESS) --rpc-url $(RPC_URL); \
	fi

get-block:
	@echo "Getting latest block number..."
	cast block-number --rpc-url $(RPC_URL)

# Format and lint
format:
	@echo "Formatting Solidity files..."
	forge fmt

lint:
	@echo "Running linter..."
	forge fmt --check

# Gas analysis
gas-snapshot:
	@echo "Creating gas snapshot..."
	forge snapshot

gas-compare:
	@echo "Comparing gas usage..."
	forge snapshot --diff

# Coverage
coverage:
	@echo "Running test coverage..."
	forge coverage

coverage-report:
	@echo "Generating coverage report..."
	forge coverage --report lcov

# Help
help:
	@echo "Available commands:"
	@echo "  build              - Install dependencies and build contracts"
	@echo "  test              - Run tests"
	@echo "  test-position-manager - Run PositionManager tests"
	@echo "  test-verbose      - Run tests with verbose output"
	@echo "  test-gas          - Run tests with gas reporting"
	@echo "  clean             - Clean build artifacts"
	@echo "  start-anvil       - Start local Anvil blockchain"
	@echo "  create-env        - Create .env file with default values"
	@echo ""
	@echo "🚀 INTEGRATED DEPLOYMENT (RECOMMENDED):"
	@echo "  deploy-all-integrated - Complete integrated system deployment"
	@echo "  quick-deploy-integrated - Quick integrated deployment + test"
	@echo "  deploy-integrated-system - Deploy integrated perps system" 
	@echo "  deploy-perps-hook-integrated - Deploy integrated PerpsHook"
	@echo "  test-integration  - Run integration test"
	@echo "  test-integration-full - Run full integration flow test"
	@echo ""
	@echo "Token Deployment:"
	@echo "  deploy-tokens     - Deploy MockUSDC and MockVETH tokens"
	@echo "  deploy-tokens-verify - Deploy tokens with verification"
	@echo "  deploy-usdc       - Deploy only MockUSDC token"
	@echo "  deploy-veth       - Deploy only MockVETH token"
	@echo "  mint-tokens       - Mint tokens to specified addresses"
	@echo ""
	@echo "Individual Contracts:"
	@echo "  deploy-margin-account - Deploy MarginAccount"
	@echo "  deploy-insurance-fund - Deploy InsuranceFund"  
	@echo "  deploy-funding-oracle - Deploy FundingOracle"
	@echo "  deploy-position-manager - Deploy PositionManager"
	@echo "  deploy-liquidation-engine - Deploy LiquidationEngine"
	@echo "  deploy-new-contracts - Deploy all new contracts (batch)"
	@echo ""
	@echo "Legacy Deployment:"
	@echo "  deploy-position-manager-verify - Deploy PositionManager with verification"
	@echo "  setup-markets     - Set up trading markets in PositionManager"
	@echo "  deploy-hook       - Deploy hook contract (with verification)"
	@echo "  deploy-hook-local - Deploy hook contract to local anvil"
	@echo "  create-pool       - Create pool and add initial liquidity"
	@echo "  add-liquidity     - Add liquidity to existing pool"
	@echo "  swap              - Execute a swap"
	@echo "  deploy-all-local  - Legacy complete local deployment flow"
	@echo "  deploy-all-mainnet- Complete mainnet deployment flow"
	@echo ""
	@echo "Development:"
	@echo "  dev-setup         - Set up development environment"
	@echo "  quick-deploy      - Legacy quick deployment and test cycle"
	@echo ""
	@echo "Utilities:"
	@echo "  check-balance ADDRESS=0x... - Check ETH balance"
	@echo "  get-block         - Get latest block number"
	@echo "  format            - Format Solidity files"
	@echo "  lint              - Run linter"
	@echo "  gas-snapshot      - Create gas snapshot"
	@echo "  gas-compare       - Compare gas usage"
	@echo "  coverage          - Run test coverage"
	@echo "  coverage-report   - Generate coverage report"
	@echo ""
	@echo "🎯 PRODUCTION DEPLOYMENT WITH HOOKMINER:"
	@echo "  deploy-production-miner-anvil      - Deploy with HookMiner on local Anvil"
	@echo "  deploy-production-miner-sepolia    - Deploy with HookMiner on Sepolia testnet"
	@echo "  deploy-production-miner-arbitrum-sepolia - Deploy with HookMiner on Arbitrum Sepolia"
	@echo "  deploy-production-miner-unichain-sepolia - Deploy with HookMiner on Unichain Sepolia"
	@echo "  deploy-production-miner-mainnet    - Deploy with HookMiner on Ethereum mainnet"
	@echo "  NOTE: HookMiner finds valid hook addresses for Uniswap v4 deployment"
	@echo "        Uses ETH/USD Pyth feed: 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"
	@echo ""
	@echo "🎯 RECOMMENDED WORKFLOW:"
	@echo "  1. make start-anvil     (in separate terminal)"
	@echo "  2. make deploy-tokens"
	@echo "  3. make deploy-all-integrated"
	@echo "  4. System ready for trading!"
	@echo ""
	@echo "Environment variables:"
	@echo "  PRIVATE_KEY       - Private key for deployments (default: anvil key #0)"
	@echo "  RPC_URL           - RPC URL (default: http://localhost:8545)"
	@echo "  ETHERSCAN_API_KEY - Etherscan API key for verification"

# Default target
.DEFAULT_GOAL := help
