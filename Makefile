# Network configuration
RPC_URL := https://sepolia.base.org
MAINNET_RPC_URL := https://mainnet.base.org

# Chain IDs
BASE_SEPOLIA_CHAIN_ID := 84532
BASE_MAINNET_CHAIN_ID := 8453

# Uniswap V4 Contract Addresses
# Sepolia
SEPOLIA_POOL_MANAGER_ADDRESS := 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408
SEPOLIA_POSITION_MANAGER_ADDRESS := 0x4b2c77d209d3405f41a037ec6c77f7f5b8e2ca80

# Mainnet
MAINNET_POOL_MANAGER_ADDRESS := 0x498581ff718922c3f8e6a244956af099b2652b2b
MAINNET_POSITION_MANAGER_ADDRESS := 0x7c5f5a4bbd8fd63184577525326123b519429bdc

# Default values
AMOUNT := 100000000 # 100 tokens (6 decimals)
COLLATERAL := 1000000000 # 1000 USDC (6 decimals)

.PHONY: check-psm swap-vcop-to-usdc swap-usdc-to-vcop check-prices help update-oracle deploy-fixed-system clean-txs check-new-oracle test-new-system test-loans test-liquidation test-psm create-position deploy-mainnet check-psm-mainnet swap-vcop-to-usdc-mainnet swap-usdc-to-vcop-mainnet check-prices-mainnet check-new-oracle-mainnet

help:
	@echo "PSM Swap Scripts"
	@echo "----------------"
	@echo "make check-psm                - Check PSM status and reserves (testnet)"
	@echo "make check-prices             - Check current PSM prices (testnet)"
	@echo "make swap-vcop-to-usdc [AMOUNT=X] - Swap VCOP for USDC (testnet)"
	@echo "make swap-usdc-to-vcop [AMOUNT=X] - Swap USDC for VCOP (testnet)"
	@echo "make update-oracle            - Update oracle to fix conversion rate (testnet)"
	@echo "make deploy-fixed-system      - Deploy entire system with fixed paridad (testnet)"
	@echo "make deploy-mainnet           - Deploy entire system to Base Mainnet"
	@echo "make clean-txs                - Clean pending transactions"
	@echo "make check-new-oracle         - Check rates from new oracle (testnet)"
	@echo "make test-new-system          - Test a swap with the newly deployed system (testnet)"
	@echo ""
	@echo "Base Mainnet Commands"
	@echo "--------------------"
	@echo "make check-psm-mainnet        - Check PSM status and reserves (mainnet)"
	@echo "make check-prices-mainnet     - Check current PSM prices (mainnet)"
	@echo "make swap-vcop-to-usdc-mainnet [AMOUNT=X] - Swap VCOP for USDC (mainnet)"
	@echo "make swap-usdc-to-vcop-mainnet [AMOUNT=X] - Swap USDC for VCOP (mainnet)"
	@echo "make check-new-oracle-mainnet - Check rates from oracle (mainnet)"
	@echo ""
	@echo "Loan System Scripts"
	@echo "----------------"
	@echo "make test-loans               - Test full loan cycle (create, add collateral, withdraw, repay)"
	@echo "make test-liquidation         - Test loan liquidation mechanism"
	@echo "make test-psm                 - Test PSM functionality (check status, swap)"

# Check PSM status (testnet)
check-psm:
	@echo "Checking PSM status on testnet..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "checkPSM()" --rpc-url $(RPC_URL)

# Check PSM status (mainnet)
check-psm-mainnet:
	@echo "Checking PSM status on mainnet..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "checkPSM()" --rpc-url $(MAINNET_RPC_URL) --chain-id $(BASE_MAINNET_CHAIN_ID)

# Check prices (testnet)
check-prices:
	@echo "Checking PSM prices on testnet..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "checkPrices()" --rpc-url $(RPC_URL) -vv

# Check prices (mainnet)
check-prices-mainnet:
	@echo "Checking PSM prices on mainnet..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "checkPrices()" --rpc-url $(MAINNET_RPC_URL) --chain-id $(BASE_MAINNET_CHAIN_ID) -vv

# Check new oracle (testnet)
check-new-oracle:
	@echo "Checking rates from the new oracle on testnet..."
	forge script script/CheckNewOracle.s.sol:CheckNewOracle --rpc-url $(RPC_URL) -vv

# Check new oracle (mainnet)
check-new-oracle-mainnet:
	@echo "Checking rates from the oracle on mainnet..."
	forge script script/CheckNewOracle.s.sol:CheckNewOracle --rpc-url $(MAINNET_RPC_URL) --chain-id $(BASE_MAINNET_CHAIN_ID) -vv

# Swap VCOP to USDC (testnet)
swap-vcop-to-usdc:
	@echo "Swapping VCOP for USDC on testnet..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapVcopToUsdc(uint256)" $(AMOUNT) --rpc-url $(RPC_URL) --broadcast -vv

# Swap VCOP to USDC (mainnet)
swap-vcop-to-usdc-mainnet:
	@echo "Swapping VCOP for USDC on mainnet..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapVcopToUsdc(uint256)" $(AMOUNT) --rpc-url $(MAINNET_RPC_URL) --chain-id $(BASE_MAINNET_CHAIN_ID) --broadcast -vv

# Swap USDC to VCOP (testnet)
swap-usdc-to-vcop:
	@echo "Swapping USDC for VCOP on testnet..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapUsdcToVcop(uint256)" $(AMOUNT) --rpc-url $(RPC_URL) --broadcast -vv

# Swap USDC to VCOP (mainnet)
swap-usdc-to-vcop-mainnet:
	@echo "Swapping USDC for VCOP on mainnet..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapUsdcToVcop(uint256)" $(AMOUNT) --rpc-url $(MAINNET_RPC_URL) --chain-id $(BASE_MAINNET_CHAIN_ID) --broadcast -vv

# Update oracle
update-oracle:
	@echo "Updating Oracle with fixed rates..."
	forge script script/UpdateOracle.s.sol:UpdateOracle --rpc-url $(RPC_URL) --broadcast -vv

# Deploy fixed system (Sepolia)
deploy-fixed-system:
	@echo "Deploying complete system with fixed parity to Sepolia..."
	forge script script/DeployFullSystemFixedParidad.s.sol:DeployFullSystemFixedParidad --rpc-url $(RPC_URL) --broadcast --gas-price 3000000000 -vv

# Deploy system to Base Mainnet
deploy-mainnet:
	@echo "Deploying complete system to Base Mainnet..."
	@echo "Using chain ID $(BASE_MAINNET_CHAIN_ID) for Base Mainnet"
	forge script script/DeployFullSystemFixedParidad.s.sol:DeployFullSystemFixedParidad --rpc-url $(MAINNET_RPC_URL) --broadcast --chain-id $(BASE_MAINNET_CHAIN_ID) -vv

# Clean transactions cache
clean-txs:
	@echo "Limpiando transacciones pendientes..."
	forge clean
	rm -rf broadcast/DeployFullSystemFixedParidad.s.sol/ 2>/dev/null || true
	@echo "Transacciones pendientes eliminadas"

# Test new system
test-new-system:
	@echo "Testing swap with new system (10 USDC)..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapUsdcToVcop(uint256)" 10000000 --rpc-url $(RPC_URL) --broadcast -vv 

# Test loan system
test-loans:
	@echo "Testing loan system..."
	forge script script/TestVCOPLoans.sol:TestVCOPLoans --rpc-url $(RPC_URL) --broadcast -vv

# Test loan liquidation
test-liquidation:
	@echo "Testing loan liquidation mechanism..."
	forge script script/TestVCOPLiquidation.sol:TestVCOPLiquidation --rpc-url $(RPC_URL) --broadcast -vv

# Test PSM functionality
test-psm:
	@echo "Testing PSM functionality..."
	forge script script/TestVCOPPSM.sol:TestVCOPPSM --rpc-url $(RPC_URL) --broadcast -vv

# Test creating position with specific collateral amount
create-position:
	@echo "Creating position with $(COLLATERAL) USDC collateral..."
	forge script script/TestVCOPLoans.sol:TestVCOPLoans --sig "createPosition(uint256)" $(COLLATERAL) --rpc-url $(RPC_URL) --broadcast -vv 