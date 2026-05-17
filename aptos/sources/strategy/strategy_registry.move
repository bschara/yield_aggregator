module YieldAggregator::strategy_registry {
    use std::signer;
    use std::table;
    use std::option;
    use aptos_framework::timestamp;

    enum RiskLevel has copy, drop, store { Low, Medium, High }

    struct Strategy has copy, drop, store {
        adapter: address,
        max_exposure: u64,
        risk: RiskLevel,
        active: bool,
        version: u64,
    }

    struct Registry has key {
        owner: address,
        strategies: table::Table<u64, Strategy>,
        next_id: u64,
    }

    #[event]
    struct StrategyAddedEvent has drop, store {
        id: u64,
        adapter: address,
        max_exposure: u64,
        timestamp: u64,
    }

    #[event]
    struct StrategyUpdatedEvent has drop, store {
        id: u64,
        version: u64,
        timestamp: u64,
    }

    #[event]
    struct StrategyRemovedEvent has drop, store {
        id: u64,
        timestamp: u64,
    }

    const ENOT_OWNER: u64 = 1;

    public entry fun init(account: &signer) {
        move_to(account, Registry {
            owner: signer::address_of(account),
            strategies: table::new<u64, Strategy>(),
            next_id: 0,
        });
    }

    public fun add_strategy(
        account: &signer,
        registry_addr: address,
        adapter: address,
        max_exposure: u64,
        risk: RiskLevel,
    ) acquires Registry {
        let registry = borrow_global_mut<Registry>(registry_addr);
        assert!(signer::address_of(account) == registry.owner, ENOT_OWNER);

        let id = registry.next_id;
        table::add(&mut registry.strategies, id, Strategy {
            adapter,
            max_exposure,
            risk,
            active: true,
            version: 1,
        });
        registry.next_id = id + 1;

        0x1::event::emit(StrategyAddedEvent {
            id,
            adapter,
            max_exposure,
            timestamp: timestamp::now_microseconds(),
        });
    }

    public entry fun update_strategy(
        account: &signer,
        registry_addr: address,
        strategy_id: u64,
        adapter: option::Option<address>,
        max_exposure: option::Option<u64>,
        active: option::Option<bool>,
    ) acquires Registry {
        let registry = borrow_global_mut<Registry>(registry_addr);
        assert!(signer::address_of(account) == registry.owner, ENOT_OWNER);

        let strategy = table::borrow_mut(&mut registry.strategies, strategy_id);

        if (option::is_some(&adapter)) { strategy.adapter = option::extract(&mut adapter); };
        if (option::is_some(&max_exposure)) { strategy.max_exposure = option::extract(&mut max_exposure); };
        if (option::is_some(&active)) { strategy.active = option::extract(&mut active); };

        strategy.version = strategy.version + 1;

        0x1::event::emit(StrategyUpdatedEvent {
            id: strategy_id,
            version: strategy.version,
            timestamp: timestamp::now_microseconds(),
        });
    }

    public entry fun remove_strategy(
        account: &signer,
        registry_addr: address,
        strategy_id: u64,
    ) acquires Registry {
        let registry = borrow_global_mut<Registry>(registry_addr);
        assert!(signer::address_of(account) == registry.owner, ENOT_OWNER);

        let strategy = table::borrow_mut(&mut registry.strategies, strategy_id);
        strategy.active = false;
        strategy.version = strategy.version + 1;

        0x1::event::emit(StrategyRemovedEvent {
            id: strategy_id,
            timestamp: timestamp::now_microseconds(),
        });
    }

    // --- Public getters (used by vault and engine) ---

    public fun is_active(registry_addr: address, id: u64): bool acquires Registry {
        table::borrow(&borrow_global<Registry>(registry_addr).strategies, id).active
    }

    public fun get_adapter(registry_addr: address, id: u64): address acquires Registry {
        table::borrow(&borrow_global<Registry>(registry_addr).strategies, id).adapter
    }

    public fun get_max_exposure(registry_addr: address, id: u64): u64 acquires Registry {
        table::borrow(&borrow_global<Registry>(registry_addr).strategies, id).max_exposure
    }

    public fun strategy_exists(registry_addr: address, id: u64): bool acquires Registry {
        table::contains(&borrow_global<Registry>(registry_addr).strategies, id)
    }

    #[test_only] public fun risk_low(): RiskLevel { RiskLevel::Low }
    #[test_only] public fun risk_medium(): RiskLevel { RiskLevel::Medium }
    #[test_only] public fun risk_high(): RiskLevel { RiskLevel::High }

}
