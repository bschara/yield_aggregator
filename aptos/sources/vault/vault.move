module YieldAggregator::yield_vault{
    use std::error;
    use std::signer;
    use std::table;
    use std::debug;
    use aptos_framework::object::{Self, DeleteRef, TransferRef};
    use aptos_framework::event::{Self};
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin;
    use aptos_framework::timestamp;
    use aptos_framework::account::{Self, SignerCapability};
    use YieldAggregator::strategy_registry;
    use YieldAggregator::adapter_interface;
    use YieldAggregator::adapter_registry;

//implement for later only keep a section of deposits in hot storgae to handle withdrawals and move the rest to hard wallet / multi-sig wallet
    struct Vault has key {
        total_assets: u128,
        total_shares: u128,

        idle_assets: u128,
        deployed_assets: u128,

        management_fee_bps: u64,
        performance_fee_bps: u64,

        // strategy_id -> amount deployed into that strategy
        allocations: table::Table<u64, u128>,

        owner: address,
        operator: address,
        paused: bool,
        signer_cap: SignerCapability,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct DepositShares has key {
        deposit_amount: u64,
        deposit_time: u64,
        shares: u64,
        transferRef: TransferRef,
        deleteRef: DeleteRef,
        creator: address,
    }

    #[event]
    struct InitVaultEvent has drop, store {
        owner: address,
        vault_addr: address,
        init_time: u64,
    }

    #[event]
    struct DepositEvent has drop, store {
        depositor: address,
        deposit_time: u64,
        shares: u64,
        deposit_amount: u64,
    }

    #[event]
    struct WithdrawEvent has drop, store {
        withdrawer: address,
        withdraw_time: u64,
        shares: u64,
        coins_out: u64,
    }

    #[event]
    struct DeployEvent has drop, store {
        strategy_id: u64,
        amount: u64,
        timestamp: u64,
    }

    #[event]
    struct RecallEvent has drop, store {
        strategy_id: u64,
        amount: u64,
        timestamp: u64,
    }

    #[event]
    struct HarvestEvent has drop, store {
        strategy_id: u64,
        timestamp: u64,
    }

    const VAULT_SEED: vector<u8> = b"CrossPlatfromYieldAggregatorVault";

    const ENOT_OPERATOR: u64 = 10;
    const ENOT_OWNER: u64 = 11;
    const EINSUFFICIENT_IDLE: u64 = 12;
    const EEXCEEDS_MAX_EXPOSURE: u64 = 13;
    const ESTRATEGY_NOT_ACTIVE: u64 = 14;
    const EINSUFFICIENT_ALLOCATION: u64 = 15;

    // Returns the deterministic vault address for a given owner.
    public fun vault_address(owner: address): address {
        account::create_resource_address(&owner, VAULT_SEED)
    }

    public entry fun init(account: &signer) {
        let owner = signer::address_of(account);
        let (vault_signer, signer_cap) = account::create_resource_account(account, VAULT_SEED);

        coin::register<aptos_coin::AptosCoin>(&vault_signer);

        move_to(&vault_signer, Vault {
            total_assets: 0,
            total_shares: 0,
            idle_assets: 0,
            deployed_assets: 0,
            management_fee_bps: 2,
            performance_fee_bps: 2,
            allocations: table::new<u64, u128>(),
            owner,
            operator: owner,
            paused: false,
            signer_cap,
        });

        0x1::event::emit(InitVaultEvent {
            owner,
            vault_addr: signer::address_of(&vault_signer),
            init_time: timestamp::now_microseconds(),
        });
    }

    public entry fun set_operator(account: &signer, vault_addr: address, new_operator: address) acquires Vault {
        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        assert!(signer::address_of(account) == vault_ref.owner, error::permission_denied(ENOT_OWNER));
        vault_ref.operator = new_operator;
    }

    // Returns the address of the DepositShares object minted to the caller.
    public fun deposit(account: &signer, deposit_amount: u64, vault_addr: address): address acquires Vault {
        let creator_addr = signer::address_of(account);

        let coins = coin::withdraw<aptos_coin::AptosCoin>(account, deposit_amount);
        assert!(coin::value(&coins) == deposit_amount, 1);

        coin::deposit<aptos_coin::AptosCoin>(vault_addr, coins);

        let shares_to_mint = compute_shares(vault_addr, deposit_amount);

        let constructor_ref = object::create_object(creator_addr);
        let obj_signer = object::generate_signer(&constructor_ref);
        let deposit_obj_addr = signer::address_of(&obj_signer);
        let transferRef = object::generate_transfer_ref(&constructor_ref);
        let deleteRef = object::generate_delete_ref(&constructor_ref);

        move_to(&obj_signer, DepositShares {
            deposit_amount,
            deposit_time: timestamp::now_microseconds(),
            shares: shares_to_mint,
            transferRef,
            deleteRef,
            creator: creator_addr,
        });

        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        vault_ref.total_assets = vault_ref.total_assets + (deposit_amount as u128);
        vault_ref.idle_assets = vault_ref.idle_assets + (deposit_amount as u128);
        vault_ref.total_shares = vault_ref.total_shares + (shares_to_mint as u128);

        0x1::event::emit(DepositEvent {
            depositor: creator_addr,
            deposit_time: timestamp::now_microseconds(),
            shares: shares_to_mint,
            deposit_amount,
        });

        deposit_obj_addr
    }

    public entry fun deposit_entry(account: &signer, deposit_amount: u64, vault_addr: address) acquires Vault {
        deposit(account, deposit_amount, vault_addr);
    }

    public entry fun withdraw(account: &signer, deposit_obj_addr: address, vault_addr: address) acquires Vault, DepositShares {
        let caller = signer::address_of(account);

        let DepositShares { deposit_amount: _, deposit_time: _, shares, transferRef: _, deleteRef, creator } =
            move_from<DepositShares>(deposit_obj_addr);
        assert!(creator == caller, error::permission_denied(2));

        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        let coins_out = (((shares as u128) * vault_ref.total_assets) / vault_ref.total_shares) as u64;
        assert!((coins_out as u128) <= vault_ref.idle_assets, error::resource_exhausted(3));

        vault_ref.total_assets = vault_ref.total_assets - (coins_out as u128);
        vault_ref.idle_assets = vault_ref.idle_assets - (coins_out as u128);
        vault_ref.total_shares = vault_ref.total_shares - (shares as u128);

        let vault_signer = account::create_signer_with_capability(&vault_ref.signer_cap);
        let coins = coin::withdraw<aptos_coin::AptosCoin>(&vault_signer, coins_out);

        coin::deposit<aptos_coin::AptosCoin>(caller, coins);
        object::delete(deleteRef);

        0x1::event::emit(WithdrawEvent {
            withdrawer: caller,
            withdraw_time: timestamp::now_microseconds(),
            shares,
            coins_out,
        });
    }

    // Deploy idle vault coins into a strategy.
    public entry fun deploy_to_strategy(
        account: &signer,
        vault_addr: address,
        registry_addr: address,
        strategy_id: u64,
        amount: u64,
        fee_amount: u64,
    ) acquires Vault {
        let caller = signer::address_of(account);
        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        assert!(caller == vault_ref.operator, error::permission_denied(ENOT_OPERATOR));
        assert!(strategy_registry::is_active(registry_addr, strategy_id), error::invalid_state(ESTRATEGY_NOT_ACTIVE));
        assert!(amount <= strategy_registry::get_max_exposure(registry_addr, strategy_id), error::invalid_argument(EEXCEEDS_MAX_EXPOSURE));
        assert!((amount as u128) <= vault_ref.idle_assets, error::resource_exhausted(EINSUFFICIENT_IDLE));

        let adapter_addr = strategy_registry::get_adapter(registry_addr, strategy_id);
        let vault_signer = account::create_signer_with_capability(&vault_ref.signer_cap);
        let coins = coin::withdraw<aptos_coin::AptosCoin>(&vault_signer, amount);
        coin::deposit<aptos_coin::AptosCoin>(adapter_addr, coins);

        adapter_interface::deposit(adapter_addr, amount, fee_amount);

        vault_ref.idle_assets = vault_ref.idle_assets - (amount as u128);
        vault_ref.deployed_assets = vault_ref.deployed_assets + (amount as u128);

        if (table::contains(&vault_ref.allocations, strategy_id)) {
            let alloc = table::borrow_mut(&mut vault_ref.allocations, strategy_id);
            *alloc = *alloc + (amount as u128);
        } else {
            table::add(&mut vault_ref.allocations, strategy_id, (amount as u128));
        };

        0x1::event::emit(DeployEvent {
            strategy_id,
            amount,
            timestamp: timestamp::now_microseconds(),
        });
    }

    // Recall coins from a strategy back into the vault.
    public entry fun recall_from_strategy(
        account: &signer,
        vault_addr: address,
        registry_addr: address,
        strategy_id: u64,
        amount: u64,
        fee_amount: u64,
    ) acquires Vault {
        let caller = signer::address_of(account);
        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        assert!(caller == vault_ref.operator, error::permission_denied(ENOT_OPERATOR));
        assert!(table::contains(&vault_ref.allocations, strategy_id), error::not_found(EINSUFFICIENT_ALLOCATION));

        let alloc = *table::borrow(&vault_ref.allocations, strategy_id);
        assert!((amount as u128) <= alloc, error::resource_exhausted(EINSUFFICIENT_ALLOCATION));

        let adapter_addr = strategy_registry::get_adapter(registry_addr, strategy_id);
        adapter_interface::withdraw(adapter_addr, amount, fee_amount);

        // Async adapters (cross-chain) update accounting via credit_bridge_return
        // when funds actually arrive. Updating here too would double-count.
        if (!adapter_registry::is_async_adapter(adapter_addr)) {
            vault_ref.idle_assets = vault_ref.idle_assets + (amount as u128);
            vault_ref.deployed_assets = vault_ref.deployed_assets - (amount as u128);
            let alloc_mut = table::borrow_mut(&mut vault_ref.allocations, strategy_id);
            *alloc_mut = *alloc_mut - (amount as u128);
        };

        0x1::event::emit(RecallEvent {
            strategy_id,
            amount,
            timestamp: timestamp::now_microseconds(),
        });
    }

    public entry fun harvest_strategy(
        account: &signer,
        vault_addr: address,
        registry_addr: address,
        strategy_id: u64,
        fee_amount: u64,
    ) acquires Vault {
        let caller = signer::address_of(account);
        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        assert!(caller == vault_ref.operator, error::permission_denied(ENOT_OPERATOR));
        assert!(strategy_registry::is_active(registry_addr, strategy_id), error::invalid_state(ESTRATEGY_NOT_ACTIVE));
        assert!(table::contains(&vault_ref.allocations, strategy_id), error::not_found(EINSUFFICIENT_ALLOCATION));

        let adapter_addr = strategy_registry::get_adapter(registry_addr, strategy_id);
        adapter_interface::harvest(adapter_addr, fee_amount);

        // Yield accrual into total_assets is handled by the adapter returning coins.
        // Real implementation: adapter deposits yield coins back to vault_addr here.

        0x1::event::emit(HarvestEvent {
            strategy_id,
            timestamp: timestamp::now_microseconds(),
        });
    }

    // Called by message_receiver when bridged funds return from Ethereum (ACTION_COMPLETE).
    // APT coins are already deposited to vault_addr by oft_bridge::lz_receive before this call.
    public fun credit_bridge_return(
        vault_addr: address,
        strategy_id: u64,
        amount: u64,
    ) acquires Vault {
        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        let amount_u128 = (amount as u128);
        vault_ref.idle_assets = vault_ref.idle_assets + amount_u128;
        vault_ref.deployed_assets = vault_ref.deployed_assets - amount_u128;
        if (table::contains(&vault_ref.allocations, strategy_id)) {
            let alloc = table::borrow_mut(&mut vault_ref.allocations, strategy_id);
            if (*alloc >= amount_u128) {
                *alloc = *alloc - amount_u128;
            } else {
                *alloc = 0;
            };
        }
    }

    // Called by message_receiver when yield is harvested on Ethereum (ACTION_HARVEST).
    // New yield coins are deposited to vault_addr by oft_bridge::lz_receive before this call.
    public fun credit_bridge_harvest(
        vault_addr: address,
        yield_amount: u64,
    ) acquires Vault {
        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        let amount_u128 = (yield_amount as u128);
        vault_ref.total_assets = vault_ref.total_assets + amount_u128;
        vault_ref.idle_assets = vault_ref.idle_assets + amount_u128;
    }

    fun compute_shares(vault_addr: address, deposit_amount: u64): u64 acquires Vault {
        let vault_ref = borrow_global<Vault>(vault_addr);
        if (vault_ref.total_assets == 0 || vault_ref.total_shares == 0) {
            deposit_amount
        } else {
            ((vault_ref.total_shares * (deposit_amount as u128)) / vault_ref.total_assets) as u64
        }
    }

    // Injects yield directly into total_assets without minting shares, simulating strategy returns.
    #[test_only]
    public fun simulate_yield(
        vault_addr: address,
        yield_amount: u128,
        mint_cap: &coin::MintCapability<aptos_coin::AptosCoin>,
    ) acquires Vault {
        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        vault_ref.total_assets = vault_ref.total_assets + yield_amount;
        vault_ref.idle_assets = vault_ref.idle_assets + yield_amount;
        let yield_coins = coin::mint((yield_amount as u64), mint_cap);
        coin::deposit<aptos_coin::AptosCoin>(vault_addr, yield_coins);
    }

    // Force-sets deployed state for tests that need to verify credit_bridge_return.
    #[test_only]
    public fun set_deployed_for_test(vault_addr: address, strategy_id: u64, amount: u128) acquires Vault {
        let vault_ref = borrow_global_mut<Vault>(vault_addr);
        vault_ref.deployed_assets = amount;
        if (table::contains(&vault_ref.allocations, strategy_id)) {
            *table::borrow_mut(&mut vault_ref.allocations, strategy_id) = amount;
        } else {
            table::add(&mut vault_ref.allocations, strategy_id, amount);
        }
    }

    #[test_only]
    public fun get_total_assets(vault_addr: address): u128 acquires Vault {
        borrow_global<Vault>(vault_addr).total_assets
    }

    #[test_only]
    public fun get_total_shares(vault_addr: address): u128 acquires Vault {
        borrow_global<Vault>(vault_addr).total_shares
    }

    #[test_only]
    public fun get_idle_assets(vault_addr: address): u128 acquires Vault {
        borrow_global<Vault>(vault_addr).idle_assets
    }

    #[test_only]
    public fun get_deployed_assets(vault_addr: address): u128 acquires Vault {
        borrow_global<Vault>(vault_addr).deployed_assets
    }

    #[test_only]
    public fun get_allocation(vault_addr: address, strategy_id: u64): u128 acquires Vault {
        let v = borrow_global<Vault>(vault_addr);
        if (table::contains(&v.allocations, strategy_id)) {
            *table::borrow(&v.allocations, strategy_id)
        } else {
            0
        }
    }

    #[test_only]
    public fun is_paused(vault_addr: address): bool acquires Vault {
        borrow_global<Vault>(vault_addr).paused
    }

    #[test_only]
    public fun get_strategies_len(_vault_addr: address): u64 {
        0
    }

    #[test_only]
    public fun was_init_vault_event_emitted(owner: address, vault_addr: address, init_time: u64): bool {
        aptos_framework::event::was_event_emitted(&InitVaultEvent { owner, vault_addr, init_time })
    }

    #[test_only]
    public fun was_deposit_event_emitted(depositor: address, deposit_time: u64, shares: u64, deposit_amount: u64): bool {
        aptos_framework::event::was_event_emitted(&DepositEvent { depositor, deposit_time, shares, deposit_amount })
    }

    #[test_only]
    public fun was_withdraw_event_emitted(withdrawer: address, withdraw_time: u64, shares: u64, coins_out: u64): bool {
        aptos_framework::event::was_event_emitted(&WithdrawEvent { withdrawer, withdraw_time, shares, coins_out })
    }

    #[test_only]
    public fun was_deploy_event_emitted(strategy_id: u64, amount: u64, timestamp: u64): bool {
        aptos_framework::event::was_event_emitted(&DeployEvent { strategy_id, amount, timestamp })
    }

    #[test_only]
    public fun was_recall_event_emitted(strategy_id: u64, amount: u64, timestamp: u64): bool {
        aptos_framework::event::was_event_emitted(&RecallEvent { strategy_id, amount, timestamp })
    }

    #[test_only]
    public fun was_harvest_event_emitted(strategy_id: u64, timestamp: u64): bool {
        aptos_framework::event::was_event_emitted(&HarvestEvent { strategy_id, timestamp })
    }

}
