module LayerZeroTest::aptos_oft {
    use aptos_framework::coin::{Coin, withdraw, deposit};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::aptos_coin;
    use layerzero::endpoint;
    use layerzero::endpoint::UaCapability;
    use std::vector;
    use layerzero_apps::oft;
    use aptos_framework::coin;
    use std::signer;
    use zro::zro;
    use layerzero::test_helpers;
    use layerzero_common::packet;
    use std::bcs;


    const SHARED_DECIMALS : u8 = 8;
    const MAX_POSSIBLE_FEE : u64 = 5 / 100;

    struct Capabilities has key {
        lz_cap: UaCapability<AptosCoin>,
    }

    public fun initialize(account: &signer) {
        coin::register<AptosCoin>(account);
        let lz_cap = oft::init_proxy_oft<AptosCoin>(account, SHARED_DECIMALS);

        move_to(account, Capabilities {
            lz_cap,
        });

    }

    public entry fun send_to_eth(
        sender: &signer,
        dst_chain_id: u64,            
        receiver_address: vector<u8>,    
        amount: u64,
    ) {
        let coin = withdraw<AptosCoin>(sender, amount);
        let min_amount = (amount * MAX_POSSIBLE_FEE) / 100;
        let (fee_rate, zro_rate) = oft::quote_fee<AptosCoin>(dst_chain_id, receiver_address, amount, false, vector::empty<u8>(), vector::empty<u8>());
        let native_fee = withdraw<AptosCoin>(sender, fee_rate);
       
        let (coin_refund, refund_native) = oft::send_coin(
            coin,
            min_amount,
            dst_chain_id,
            receiver_address,  
            native_fee,
            vector::empty<u8>(),          
            vector::empty<u8>(),          
        );

        deposit(signer::address_of(sender), refund_native);
        coin::destroy_zero(coin_refund);
    }




    #[test(
        aptos = @aptos_framework,
        layerzero = @layerzero,
        alice = @0xABCD,
        bob = @0xAABB
    )]
    fun test_send_to_eth_flow(
        aptos: &signer,
        layerzero: &signer,
        alice: &signer,
        bob: &signer
    ) {
        initialize(aptos);

        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos);

        coin::register<AptosCoin>(alice);
        coin::register<AptosCoin>(bob);

        let alice_addr = signer::address_of(alice);
        // coin::mint<AptosCoin>(aptos, signer::address_of(alice), 1_000_000);
        let coins = coin::mint<AptosCoin>(1000000, &mint_cap);
        coin::deposit(alice_addr, coins);
 
        let bob_addr = signer::address_of(bob);
        let bob_addr_bytes = bcs::to_bytes(&bob_addr);

        let dst_chain_id: u64 = 100; 
        let dist_receiv = vector::empty<u8>();
        let amount: u64 = 100_000;

        let (fee, zro_rate) = oft::quote_fee<AptosCoin>(
            dst_chain_id,
            dist_receiv,
            amount,
            false,
            vector::empty<u8>(),
            vector::empty<u8>()
        );

       send_to_eth(
            alice,
            dst_chain_id,
            dist_receiv,
            amount
        );

        let alice_balance = coin::balance<AptosCoin>(alice_addr);
        assert!(alice_balance < 1_000_000, 0);

        let payload = oft::encode_send_payload_for_testing(
            bob_addr_bytes, amount
        );
        let nonce = 1;
        let emitted_packet = packet::new_packet(
            1, 
            vector::empty<u8>(), 
            dst_chain_id,
            dist_receiv,
            nonce,
            payload
        );
        test_helpers::deliver_packet<AptosCoin>(layerzero, layerzero, emitted_packet, 0);

        oft::claim<AptosCoin>(bob);

        let bob_balance = coin::balance<AptosCoin>(bob_addr);
        assert!(bob_balance > 0, 1);

        assert!(oft::get_total_locked_coin<AptosCoin>() == 0, 2);
        coin::destroy_mint_cap(mint_cap);
        coin::destroy_burn_cap(burn_cap);

    }

}
