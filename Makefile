# Network configuration
RPC_URL := https://sepolia.base.org

# Default values
AMOUNT := 100000000 # 100 tokens (6 decimals)
COLLATERAL := 1000000000 # 1000 USDC (6 decimals)

.PHONY: check-psm swap-vcop-to-usdc swap-usdc-to-vcop check-prices help update-oracle deploy-fixed-system clean-txs check-new-oracle test-new-system test-loans test-liquidation test-psm create-position

help:
	@echo "PSM Swap Scripts"
	@echo "----------------"
	@echo "make check-psm                - Check PSM status and reserves"
	@echo "make check-prices             - Check current PSM prices"
	@echo "make swap-vcop-to-usdc [AMOUNT=X] - Swap VCOP for USDC (default 100 VCOP)"
	@echo "make swap-usdc-to-vcop [AMOUNT=X] - Swap USDC for VCOP (default 100 USDC)"
	@echo "make update-oracle            - Update oracle to fix conversion rate"
	@echo "make deploy-fixed-system      - Deploy entire system with fixed paridad"
	@echo "make clean-txs                - Clean pending transactions"
	@echo "make check-new-oracle         - Check rates from new oracle"
	@echo "make test-new-system          - Test a swap with the newly deployed system"
	@echo ""
	@echo "Loan System Scripts"
	@echo "----------------"
	@echo "make test-loans               - Test full loan cycle (create, add collateral, withdraw, repay)"
	@echo "make test-liquidation         - Test loan liquidation mechanism"
	@echo "make test-psm                 - Test PSM functionality (check status, swap)"

# Check PSM status
check-psm:
	@echo "Checking PSM status..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "checkPSM()" --rpc-url $(RPC_URL)

# Check prices
check-prices:
	@echo "Checking PSM prices..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "checkPrices()" --rpc-url $(RPC_URL) -vv

# Check new oracle
check-new-oracle:
	@echo "Checking rates from the new oracle..."
	forge script script/CheckNewOracle.s.sol:CheckNewOracle --rpc-url $(RPC_URL) -vv

# Swap VCOP to USDC
swap-vcop-to-usdc:
	@echo "Swapping VCOP for USDC..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapVcopToUsdc(uint256)" $(AMOUNT) --rpc-url $(RPC_URL) --broadcast -vv

# Swap USDC to VCOP
swap-usdc-to-vcop:
	@echo "Swapping USDC for VCOP..."
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapUsdcToVcop(uint256)" $(AMOUNT) --rpc-url $(RPC_URL) --broadcast -vv

# Update oracle
update-oracle:
	@echo "Updating Oracle with fixed rates..."
	forge script script/UpdateOracle.s.sol:UpdateOracle --rpc-url $(RPC_URL) --broadcast -vv

# Deploy fixed system
deploy-fixed-system:
	@echo "Deploying complete system with fixed parity..."
	forge script script/DeployFullSystemFixedParidad.s.sol:DeployFullSystemFixedParidad --rpc-url $(RPC_URL) --broadcast --gas-price 3000000000 -vv

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