module YieldAggregator::strategy_executor {
    use std::signer;
    use std::table;
    use std::option;
    use aptos_framework::timestamp;
    use YieldAggregator::yield_vault;

    enum ExecutionActionType has copy, drop, store { Deposit, Withdraw, Harvest, Exit }

    struct ExecutionIntent has copy, drop, store {
        strategy_id: u64,
        action: ExecutionActionType,
        amount: u64,
        target_chain: option::Option<u64>,
        nonce: u64,
    }

    struct ExecutionState has key {
        operator: address,
        executed_nonces: table::Table<u64, bool>,
    }

    #[event]
    struct ExecutionEvent has drop, store {
        strategy_id: u64,
        action: ExecutionActionType,
        amount: u64,
        executor: address,
        timestamp: u64,
    }

    const ENOT_OPERATOR: u64 = 1;
    const ENONCE_ALREADY_USED: u64 = 2;

    public entry fun init(account: &signer) {
        move_to(account, ExecutionState {
            operator: signer::address_of(account),
            executed_nonces: table::new<u64, bool>(),
        });
    }

    public entry fun set_operator(account: &signer, new_operator: address) acquires ExecutionState {
        let state = borrow_global_mut<ExecutionState>(signer::address_of(account));
        assert!(signer::address_of(account) == state.operator, ENOT_OPERATOR);
        state.operator = new_operator;
    }

    // Submit a signed intent to execute a strategy action.
    // Prevents replay attacks via nonce tracking.
    public fun execute_intent(
        account: &signer,
        engine_addr: address,
        vault_addr: address,
        registry_addr: address,
        intent: ExecutionIntent,
    ) acquires ExecutionState {
        let exec_state = borrow_global_mut<ExecutionState>(engine_addr);
        assert!(signer::address_of(account) == exec_state.operator, ENOT_OPERATOR);
        assert!(!table::contains(&exec_state.executed_nonces, intent.nonce), ENONCE_ALREADY_USED);
        table::add(&mut exec_state.executed_nonces, intent.nonce, true);

        match (intent.action) {
            ExecutionActionType::Deposit => {
                yield_vault::deploy_to_strategy(account, vault_addr, registry_addr, intent.strategy_id, intent.amount);
            },
            ExecutionActionType::Withdraw => {
                yield_vault::recall_from_strategy(account, vault_addr, registry_addr, intent.strategy_id, intent.amount);
            },
            ExecutionActionType::Harvest => {
                yield_vault::harvest_strategy(account, vault_addr, registry_addr, intent.strategy_id);
            },
            ExecutionActionType::Exit => {
                yield_vault::recall_from_strategy(account, vault_addr, registry_addr, intent.strategy_id, intent.amount);
            },
        };

        0x1::event::emit(ExecutionEvent {
            strategy_id: intent.strategy_id,
            action: intent.action,
            amount: intent.amount,
            executor: signer::address_of(account),
            timestamp: timestamp::now_microseconds(),
        });
    }

    #[test_only]
    public fun make_deposit_intent(strategy_id: u64, amount: u64, nonce: u64): ExecutionIntent {
        ExecutionIntent { strategy_id, action: ExecutionActionType::Deposit, amount, target_chain: option::none(), nonce }
    }

    #[test_only]
    public fun make_withdraw_intent(strategy_id: u64, amount: u64, nonce: u64): ExecutionIntent {
        ExecutionIntent { strategy_id, action: ExecutionActionType::Withdraw, amount, target_chain: option::none(), nonce }
    }

    #[test_only]
    public fun make_harvest_intent(strategy_id: u64, nonce: u64): ExecutionIntent {
        ExecutionIntent { strategy_id, action: ExecutionActionType::Harvest, amount: 0, target_chain: option::none(), nonce }
    }

    #[test_only]
    public fun make_exit_intent(strategy_id: u64, amount: u64, nonce: u64): ExecutionIntent {
        ExecutionIntent { strategy_id, action: ExecutionActionType::Exit, amount, target_chain: option::none(), nonce }
    }

}
