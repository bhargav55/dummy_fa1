module warpgate::swap_utils {
    use std::string;
    use aptos_std::type_info;
    use aptos_std::comparator;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use std::bcs;
    const EQUAL: u8 = 0;
    const SMALLER: u8 = 1;
    const GREATER: u8 = 2;
    
    const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 0;
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 1;
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 2;
    const ERROR_INSUFFICIENT_OUTPOT_AMOUNT: u64 = 3;
    const ERROR_SAME_TOKEN: u64 = 4;
    
    // Calculate output amount for a swap
    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        swap_fee: u128,
    ): u64 {
        assert!(amount_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);
        
        let amount_in_with_fee = (amount_in as u128) * (10000u128 - (swap_fee as u128));
        let numerator = amount_in_with_fee * (reserve_out as u128);
        let denominator = (reserve_in as u128) * 10000u128 + amount_in_with_fee;
        ((numerator / denominator) as u64)
    }
    
    // Calculate input amount needed for a desired output
    public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
        swap_fee: u128,
    ): u64 {
        assert!(amount_out > 0, ERROR_INSUFFICIENT_OUTPOT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);
        assert!(amount_out < reserve_out, ERROR_INSUFFICIENT_LIQUIDITY);
        
        let fee_multiplier = 10000u128 - swap_fee;
        let numerator = (reserve_in as u128) * (amount_out as u128) * 10000u128;
        let denominator = fee_multiplier * ((reserve_out as u128) - (amount_out as u128));
        (((numerator / denominator) as u64) + 1u64)
    }
    
    // Calculate proportional amount based on reserves
    public fun quote(amount_x: u64, reserve_x: u64, reserve_y: u64): u64 {
        assert!(amount_x > 0, ERROR_INSUFFICIENT_AMOUNT);
        assert!(reserve_x > 0 && reserve_y > 0, ERROR_INSUFFICIENT_LIQUIDITY);
        (((amount_x as u128) * (reserve_y as u128) / (reserve_x as u128)) as u64)
    }
    
public fun sort_tokens(
    token_a: Object<Metadata>,
    token_b: Object<Metadata>
): (Object<Metadata>, Object<Metadata>, bool) {
    let addr_a = object::object_address(&token_a);
    let addr_b = object::object_address(&token_b);
    
    assert!(addr_a != addr_b, ERROR_SAME_TOKEN);
    
    let addr_a_bytes = bcs::to_bytes(&addr_a);
    let addr_b_bytes = bcs::to_bytes(&addr_b);
    
    let result = comparator::compare(&addr_a_bytes, &addr_b_bytes);
    
    if (comparator::is_smaller_than(&result)) {
        (token_a, token_b, false)
    } else {
        (token_b, token_a, true)
    }
}

    // Get token info for display
    public fun get_token_info(token: Object<Metadata>): string::String {
        fungible_asset::name(token)
    }
    
    // Helper functions for comparison
    public fun get_smaller_enum(): u8 {
        SMALLER
    }
    
    public fun get_greater_enum(): u8 {
        GREATER
    }
    
    public fun get_equal_enum(): u8 {
        EQUAL
    }
    
 public fun compare_tokens(
    token_a: Object<Metadata>,
    token_b: Object<Metadata>
): u8 {
    let addr_a = object::object_address(&token_a);
    let addr_b = object::object_address(&token_b);
    
    let addr_a_bytes = bcs::to_bytes(&addr_a);
    let addr_b_bytes = bcs::to_bytes(&addr_b);
    
    let result = comparator::compare(&addr_a_bytes, &addr_b_bytes);
    
    if (comparator::is_smaller_than(&result)) {
        SMALLER
    } else if (comparator::is_greater_than(&result)) {
        GREATER
    } else {
        EQUAL
    }
}
}