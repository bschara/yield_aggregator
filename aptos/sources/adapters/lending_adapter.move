module YieldAggregator::lending_adapter {
    use std::signer;
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account::{Self, SignerCapability};
    use YieldAggregator::adapter_registry;

    const ADAPTER_SEED: vector<u8> = b"LendingAdapter";

    struct LendingAdapter has key {
        owner: address,
        signer_cap: SignerCapability,
        vault_addr: address,
        deposited: u128,
    }

    public entry fun init(account: &signer, vault_addr: address) {
        let owner = signer::address_of(account);
        let (adapter_signer, signer_cap) = account::create_resource_account(account, ADAPTER_SEED);
        coin::register<AptosCoin>(&adapter_signer);

        move_to(&adapter_signer, LendingAdapter {
            owner,
            signer_cap,
            vault_addr,
            deposited: 0,
        });

        adapter_registry::register_adapter(&adapter_signer, adapter_registry::type_lending(), false);
    }

    public fun adapter_address(owner: address): address {
        account::create_resource_address(&owner, ADAPTER_SEED)
    }

    // TODO: swap APT -> lending token and deposit into protocol (Aries, Echelon, etc.)
    public fun trigger_deposit(_adapter_addr: address, _amount: u64, _fee_amount: u64) {}

    // TODO: withdraw from lending protocol and return APT to vault
    public fun trigger_withdraw(_adapter_addr: address, _amount: u64, _fee_amount: u64) {}

    // TODO: claim accumulated interest from lending protocol and send to vault
    public fun trigger_harvest(_adapter_addr: address, _fee_amount: u64) {}

    // TODO: withdraw all funds immediately from lending protocol
    public fun trigger_emergency_exit(_adapter_addr: address, _fee_amount: u64) {}
}
