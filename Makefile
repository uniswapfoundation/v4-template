# Network configuration
RPC_URL := https://sepolia.base.org

# Default values
AMOUNT := 100000000 # 100 tokens (6 decimals)

.PHONY: check-psm swap-vcop-to-usdc swap-usdc-to-vcop check-prices help update-oracle deploy-fixed-system clean-txs check-new-oracle

help:
	@echo "PSM Swap Scripts"
	@echo "----------------"
	@echo "make check-psm                - Check PSM status and reserves"
	@echo "make check-prices             - Check current PSM prices"
	@echo "make swap-vcop-to-usdc [AMOUNT=X] - Swap VCOP for USDC (default 100 VCOP)"
	@echo "make swap-usdc-to-vcop [AMOUNT=X] - Swap USDC for VCOP (default 100 USDC)"
	@echo "make update-oracle            - Update oracle to fix conversion rate"
	@echo "make deploy-fixed-system      - Deploy entire system with fixed paridad"
	@echo "make clean-txs                - Clean pending transactions (before redeployment)"
	@echo "make check-new-oracle         - Check rates from the new oracle"

# Check PSM status
check-psm:
	forge script script/PsmCheck.s.sol:PsmCheckScript --rpc-url $(RPC_URL) -vv

# Check prices
check-prices:
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "checkPrices()" --rpc-url $(RPC_URL) -vv

# Check new oracle
check-new-oracle:
	forge script script/CheckNewOracle.s.sol:CheckNewOracle --rpc-url $(RPC_URL) -vv

# Swap VCOP to USDC
swap-vcop-to-usdc:
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapVcopToUsdc(uint256)" $(AMOUNT) --rpc-url $(RPC_URL) --broadcast -vv

# Swap USDC to VCOP
swap-usdc-to-vcop:
	forge script script/CustomPsmSwap.s.sol:CustomPsmSwapScript --sig "swapUsdcToVcop(uint256)" $(AMOUNT) --rpc-url $(RPC_URL) --broadcast -vv

# Update oracle
update-oracle:
	forge script script/UpdateOracle.s.sol:UpdateOracle --rpc-url $(RPC_URL) --broadcast -vv

# Deploy fixed system
deploy-fixed-system:
	forge script script/DeployFullSystemFixedParidad.s.sol:DeployFullSystemFixedParidad --rpc-url $(RPC_URL) --broadcast --gas-price 3000000000 -vv

# Clean transactions cache
clean-txs:
	@echo "Limpiando transacciones pendientes..."
	forge clean
	rm -rf broadcast/DeployFullSystemFixedParidad.s.sol/ 2>/dev/null || true
	@echo "Transacciones pendientes eliminadas" 