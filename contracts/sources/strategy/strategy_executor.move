// module YieldAggregator::strategy_executor {
//     use std::signer;
//     use std::table;
//     use YieldAggregator::yield_vault::{Treasury};
//     use YieldAggregator::strategy_registry::{Registry, Strategy};
//     use aptos_framework::event;
//     use std::option;


//     enum ExecutionActionType { Deposit, Withdraw, Harvest, Exit }

//     struct ExecutionIntent has copy, drop, store {
//         strategy_id: u64,
//         action: u8,       
//         amount: u64,
//         target_chain: option::Option<u64>, 
//         nonce: u64,
//     }

    
//     struct ExecutionState has key {
//         executed_nonces: table::Table<u64, bool>,
//     }

    
//     struct ExecutionEvent has copy, drop, store {
//         strategy_id: u64,
//         action: ExecutionActionType,
//         amount: u64,
//         executor: address,
//         timestamp: u64,
//     }

//     public entry fun init(account: &signer) {
//         move_to(account, ExecutionState {
//             executed_nonces: table::new<u64, bool>(),
//         });
// }

// fun validate_intent(
//     vault: &Treasury,
//     registry: &Registry,
//     intent: &ExecutionIntent
// ) acquires Strategy {
//     let strategy = table::borrow(&registry.strategies, intent.strategy_id);

//     assert!(strategy.active, 1);
//     assert!(intent.amount <= strategy.max_exposure, 2); 
//     assert!(vault.vault_balance >= intent.amount, 3); 
// }

// public entry fun execute_intent(
//     account: &signer,
//     vault_addr: address,
//     registry_addr: address,
//     intent: ExecutionIntent
// ) acquires Treasury, Registry, ExecutionState {
//     let vault = borrow_global_mut<Treasury>(vault_addr);
//     let registry = borrow_global<Registry>(registry_addr);
//     let exec_state = borrow_global_mut<ExecutionState>(signer::address_of(account));

   
//     assert!(!table::contains(&exec_state.executed_nonces, intent.nonce), 10);
//     table::add(&mut exec_state.executed_nonces, intent.nonce, true);

   
//     validate_intent(vault, registry, &intent);

    
//     match (intent.action) {
//         Deposit => deposit_to_strategy(vault, registry, &intent),
//         Withdraw => withdraw_from_strategy(vault, registry, &intent),
//         Harvest => harvest_strategy(vault, registry, &intent),
//         Exit => emergency_exit_strategy(vault, registry, &intent),
//         _ => assert!(false, 20)
//     };

//     let event = ExecutionEvent {
//         strategy_id: intent.strategy_id,
//         action: intent.action,
//         amount: intent.amount,
//         executor: signer::address_of(account),
//         timestamp: aptos_framework::timestamp::now_seconds()
//     };
//     // Emit logic here (can use Aptos event handle)
// }


// fun deposit_to_strategy(vault: &mut Treasury, registry: &Registry, intent: &ExecutionIntent) acquires Strategy {
//     let strategy = table::borrow(&registry.strategies, intent.strategy_id);
    
//     // Call adapter deposit
    
//     vault.vault_balance = vault.vault_balance - intent.amount;
//     // record per-strategy exposure if needed
// }

// fun withdraw_from_strategy(vault: &mut Treasury, registry: &Registry, intent: &ExecutionIntent) acquires Strategy {
//     let strategy = table::borrow(&registry.strategies, intent.strategy_id);
    
//     // Call adapter withdraw
//     // pseudo: Adapter::withdraw(strategy.adapter, intent.amount);
    
//     // Update vault_balance and exposure
//     vault.vault_balance = vault.vault_balance + intent.amount;
// }


// }
