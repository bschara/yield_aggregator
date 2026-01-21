module YieldAggregator::adapter_interface {
    use aptos_framework::coin::{Coin};
    
    public fun deposit(adapter_addr: address, amount: u64){}
    public fun withdraw(adapter_addr: address, amount: u64){}
    public fun harvest(adapter_addr: address){}
    public fun emergency_exit(adapter_addr: address){}
}
