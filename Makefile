.PHONY: test test-aptos test-eth test-e2e

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
