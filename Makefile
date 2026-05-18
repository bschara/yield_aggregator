.PHONY: test test-aptos test-eth test-e2e install-offchain start-policy start-offchain

test: test-aptos test-eth

test-aptos:
	cd aptos && aptos move test

test-eth:
	cd ethereum && npm test

test-e2e:
	aptos node run-local-testnet --with-faucet &
	cd ethereum && npx hardhat node &
	sleep 5
	cd e2e-tests && npm test
	pkill -f "aptos node run-local-testnet" || true
	pkill -f "hardhat node" || true

install-offchain:
	cd offchain && npm install
	pip install -r offchain/requirements.txt

# Start the Python policy server (Yield + Risk engines)
start-policy:
	cd offchain && python3 -m uvicorn ai.server:app --host 0.0.0.0 --port 8001 --reload

# Start the TypeScript main loop (requires policy server running)
start-offchain:
	cd offchain && npm start
