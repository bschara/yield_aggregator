module YieldAggregator::strategy_registry {
    use std::signer;
    use std::table;

    enum RiskLevel { Low, Medium, High }

    struct Strategy has copy, drop, store {
        adapter: address,          
        max_exposure: u64,         
        risk: RiskLevel,
        active: bool,             
        version: u64,            
    }

  
    struct Registry has key {
        strategies: table::Table<u64, Strategy>, 
        next_id: u64,                           
    }


    public entry fun init(account: &signer) {
        move_to(account, Registry {
            strategies: table::new<u64, Strategy>(),
            next_id: 0,
        });
    }

    public entry fun add_strategy(
    account: &signer,
    adapter: address,
    max_exposure: u64,
    risk: RiskLevel
) acquires Registry {
    let registry = borrow_global_mut<Registry>(signer::address_of(account));
    let id = registry.next_id;

    table::add(&mut registry.strategies, id, Strategy {
        adapter,
        max_exposure,
        risk,
        active: true,
        version: 1,
    });

    registry.next_id = id + 1;
}

public entry fun update_strategy(
    account: &signer,
    strategy_id: u64,
    adapter: option::Option<address>,
    max_exposure: option::Option<u64>,
    risk: option::Option<RiskLevel>,
    active: option::Option<bool>
) acquires Registry {
    let registry = borrow_global_mut<Registry>(signer::address_of(account));
    let strategy = table::borrow_mut(&mut registry.strategies, strategy_id);

    if (option::is_some(&adapter)) { strategy.adapter = option::extract(adapter); }
    if (option::is_some(&max_exposure)) { strategy.max_exposure = option::extract(max_exposure); }
    if (option::is_some(&risk)) { strategy.risk = option::extract(risk); }
    if (option::is_some(&active)) { strategy.active = option::extract(active); }

    strategy.version = strategy.version + 1;
}

public entry fun remove_strategy(account: &signer, strategy_id: u64) acquires Registry {
    let registry = borrow_global_mut<Registry>(signer::address_of(account));
    let strategy = table::borrow_mut(&mut registry.strategies, strategy_id);
    strategy.active = false; 
    strategy.version = strategy.version + 1;
}



}
