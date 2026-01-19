module YieldAggregator::yield_vault{
    use std::error;
    use std::signer;
    use std::vector;
    use std::debug;
    use aptos_framework::object::{Self, Object, DeleteRef, ExtendRef, TransferRef};
    use aptos_framework::event::{Self};
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use aptos_framework::account;   


    const NOT_CONTRACT_OWNER: u8 = 1;


    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Treasury has key {
            total_shares: u64,
            vault_balance: u64,
            // deployer_addr: address,
            eth_remote_balance: u64,
            extendRef: ExtendRef,
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

    public entry fun init(account: &signer) {

        let name: vector<u8> = b"CrossPlatfromYieldAggregatorVault";
        let constr_ref = object::create_named_object(account, name);
        let extenRef = object::generate_extend_ref(&constr_ref);

        move_to(account, Treasury {
            total_shares: 0,
            vault_balance: 0,
            eth_remote_balance: 0,
            extendRef: extenRef,
        });
    }


    public fun deposit(account: &signer, deposit_amount: u64, vault_addr: address) acquires Treasury{
       let shares_to_mint =  compute_shares(vault_addr, deposit_amount);
       let creator_addr = signer::address_of(account);

    //    let constrcutor_ref = object::create_object_from_account

    }


    fun compute_shares(vault_addr: address, deposit_amount: u64): u64 acquires Treasury{
        let vault_ref = borrow_global_mut<Treasury>(vault_addr);
        let shares_to_mint = ((vault_ref.total_shares + vault_ref.eth_remote_balance) * deposit_amount) / vault_ref.vault_balance;
        shares_to_mint
     }

}