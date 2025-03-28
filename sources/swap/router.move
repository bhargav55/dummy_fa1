module warpgate::router {
    use std::signer;
    
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    
    use warpgate::swap;
    use warpgate::swap_utils;
    
    // Error constants
    const E_OUTPUT_LESS_THAN_MIN: u64 = 0;
    const E_INPUT_MORE_THAN_MAX: u64 = 1;
    const E_INSUFFICIENT_X_AMOUNT: u64 = 2;
    const E_INSUFFICIENT_Y_AMOUNT: u64 = 3;
    const E_PAIR_NOT_CREATED: u64 = 4;
    
    // Create a pair from 2 tokens
    public entry fun create_pair(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        swap_fee: u128
    ) {
        // Automatically sort tokens
        let (sorted_x, sorted_y, _) = swap_utils::sort_tokens(token_x, token_y);
        swap::create_pair(sender, sorted_x, sorted_y, swap_fee);
    }
    
    // Add liquidity to an existing pair or create it if needed
    public entry fun add_liquidity(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64,
        swap_fee: u128
    ) {
        // Check if pair exists, create if not
        if (!is_pair_created(token_x, token_y)) {
            create_pair(sender, token_x, token_y, swap_fee);
        };
        // Register for LP token
        register_lp(sender, token_x, token_y);

        // Register for both tokens
        register_token(sender, token_x);
        register_token(sender, token_y);
        
        // Add liquidity
        let (amount_x, amount_y, _) = swap::add_liquidity(
            sender,
            token_x,
            token_y,
            amount_x_desired,
            amount_y_desired
        );
        
        // Check minimums
        assert!(amount_x >= amount_x_min, E_INSUFFICIENT_X_AMOUNT);
        assert!(amount_y >= amount_y_min, E_INSUFFICIENT_Y_AMOUNT);
    }
    
    // Check if a pair exists
    fun is_pair_created(token_x: Object<Metadata>, token_y: Object<Metadata>): bool {
        swap::is_pair_created(token_x, token_y)
    }
    
    // Remove liquidity from a pair
    public entry fun remove_liquidity(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        liquidity: u64,
        amount_x_min: u64,
        amount_y_min: u64
    ) {
        assert!(is_pair_created(token_x, token_y), E_PAIR_NOT_CREATED);
        
        let (amount_x, amount_y) = swap::remove_liquidity(
            sender,
            token_x,
            token_y,
            liquidity
        );
        
        assert!(amount_x >= amount_x_min, E_INSUFFICIENT_X_AMOUNT);
        assert!(amount_y >= amount_y_min, E_INSUFFICIENT_Y_AMOUNT);
    }
    
    // Swap exact input amount of X to minimum amount of Y
    public entry fun swap_exact_input(
        sender: &signer,
        token_in: Object<Metadata>,
        token_out: Object<Metadata>,
        amount_in: u64,
        amount_out_min: u64
    ) {
        assert!(is_pair_created(token_in, token_out), E_PAIR_NOT_CREATED);
        
        let output_amount = if (swap_utils::compare_tokens(token_in, token_out) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_in, token_out, amount_in, signer::address_of(sender))
        } else {
            swap::swap_exact_y_to_x(sender, token_out, token_in, amount_in, signer::address_of(sender))
        };
        
        assert!(output_amount >= amount_out_min, E_OUTPUT_LESS_THAN_MIN);
    }
    
    // Swap minimum amount of X to exact output amount of Y
    public entry fun swap_exact_output(
        sender: &signer,
        token_in: Object<Metadata>,
        token_out: Object<Metadata>,
        amount_out: u64,
        amount_in_max: u64
    ) {
        assert!(is_pair_created(token_in, token_out), E_PAIR_NOT_CREATED);
        
        let input_amount = if (swap_utils::compare_tokens(token_in, token_out) == swap_utils::get_smaller_enum()) {
            swap::swap_x_to_exact_y(sender, token_in, token_out, amount_out, signer::address_of(sender))
        } else {
            swap::swap_y_to_exact_x(sender, token_out, token_in, amount_out, signer::address_of(sender))
        };
        
        assert!(input_amount <= amount_in_max, E_INPUT_MORE_THAN_MAX);
    }
    
    // View function to get expected output amount
    #[view]
    public fun get_amount_out(
        amount_in: u64,
        token_in: Object<Metadata>,
        token_out: Object<Metadata>
    ): u64 {
        assert!(is_pair_created(token_in, token_out), E_PAIR_NOT_CREATED);
        
        let (reserve_in, reserve_out, _) = if (swap_utils::compare_tokens(token_in, token_out) == swap_utils::get_smaller_enum()) {
            swap::token_reserves(token_in, token_out)
        } else {
            let (reserve_out, reserve_in, timestamp) = swap::token_reserves(token_out, token_in);
            (reserve_in, reserve_out, timestamp)
        };
        let mm_fee = swap::get_mm_fee();
        amount_in = amount_in - (((amount_in as u128) * mm_fee) / 10000 as u64);
        let fee = swap::get_pair_fee(token_in, token_out);
        swap_utils::get_amount_out(amount_in, reserve_in, reserve_out, fee)
    }
    
    // View function to get required input amount
    #[view]
    public fun get_amount_in(
        amount_out: u64,
        token_in: Object<Metadata>,
        token_out: Object<Metadata>
    ): u64 {
        assert!(is_pair_created(token_in, token_out), E_PAIR_NOT_CREATED);
        
        let (reserve_in, reserve_out, _) = if (swap_utils::compare_tokens(token_in, token_out) == swap_utils::get_smaller_enum()) {
            swap::token_reserves(token_in, token_out)
        } else {
            let (reserve_out, reserve_in, timestamp) = swap::token_reserves(token_out, token_in);
            (reserve_in, reserve_out, timestamp)
        };
        
        let fee = swap::get_pair_fee(token_in, token_out);
        swap_utils::get_amount_in(amount_out, reserve_in, reserve_out, fee)
    }
    
    // Quote price based on reserves
    #[view]
    public fun quote(
        amount_x: u64,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ): u64 {
        assert!(is_pair_created(token_x, token_y), E_PAIR_NOT_CREATED);
        
        let (reserve_x, reserve_y, _) = swap::token_reserves(token_x, token_y);
        swap_utils::quote(amount_x, reserve_x, reserve_y)
    }
    
    // Multi-hop swap (2 hops)
    public entry fun swap_exact_input_doublehop(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        token_z: Object<Metadata>,
        amount_in: u64,
        amount_out_min: u64
    ) {
        // Verify pairs exist
        assert!(is_pair_created(token_x, token_y), E_PAIR_NOT_CREATED);
        assert!(is_pair_created(token_y, token_z), E_PAIR_NOT_CREATED);
        
        // First hop: X -> Y
        let sender_addr = signer::address_of(sender);
        let y_amount = if (swap_utils::compare_tokens(token_x, token_y) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_x, token_y, amount_in, sender_addr)
        } else {
            swap::swap_exact_y_to_x(sender, token_y, token_x, amount_in, sender_addr)
        };
        
        // Second hop: Y -> Z
        let z_amount = if (swap_utils::compare_tokens(token_y, token_z) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_y, token_z, y_amount, sender_addr)
        } else {
            swap::swap_exact_y_to_x(sender, token_z, token_y, y_amount, sender_addr)
        };
        
        assert!(z_amount >= amount_out_min, E_OUTPUT_LESS_THAN_MIN);
    }
    
    // Multi-hop swap with exact output (2 hops)
    public entry fun swap_exact_output_doublehop(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        token_z: Object<Metadata>,
        amount_out: u64,
        amount_in_max: u64
    ) {
        // Verify pairs exist
        assert!(is_pair_created(token_x, token_y), E_PAIR_NOT_CREATED);
        assert!(is_pair_created(token_y, token_z), E_PAIR_NOT_CREATED);
        
        // Calculate amounts from back to front
        // First get amount of Y needed for Z
        let y_needed = if (swap_utils::compare_tokens(token_y, token_z) == swap_utils::get_smaller_enum()) {
            let (reserve_y, reserve_z, _) = swap::token_reserves(token_y, token_z);
            let fee = swap::get_pair_fee(token_y, token_z);
            swap_utils::get_amount_in(amount_out, reserve_y, reserve_z, fee)
        } else {
            let (reserve_z, reserve_y, _) = swap::token_reserves(token_z, token_y);
            let fee = swap::get_pair_fee(token_z, token_y);
            swap_utils::get_amount_in(amount_out, reserve_y, reserve_z, fee)
        };
        
        // Then get amount of X needed for Y
        let x_needed = if (swap_utils::compare_tokens(token_x, token_y) == swap_utils::get_smaller_enum()) {
            let (reserve_x, reserve_y, _) = swap::token_reserves(token_x, token_y);
            let fee = swap::get_pair_fee(token_x, token_y);
            swap_utils::get_amount_in(y_needed, reserve_x, reserve_y, fee)
        } else {
            let (reserve_y, reserve_x, _) = swap::token_reserves(token_y, token_x);
            let fee = swap::get_pair_fee(token_y, token_x);
            swap_utils::get_amount_in(y_needed, reserve_x, reserve_y, fee)
        };
        
        assert!(x_needed <= amount_in_max, E_INPUT_MORE_THAN_MAX);
        
        // Execute swaps
        let sender_addr = signer::address_of(sender);
        
        // First hop: X -> Y (exact output)
        if (swap_utils::compare_tokens(token_x, token_y) == swap_utils::get_smaller_enum()) {
            swap::swap_x_to_exact_y(sender, token_x, token_y, y_needed, sender_addr);
        } else {
            swap::swap_y_to_exact_x(sender, token_y, token_x, y_needed, sender_addr);
        };
        
        // Second hop: Y -> Z (exact output)
        if (swap_utils::compare_tokens(token_y, token_z) == swap_utils::get_smaller_enum()) {
            swap::swap_x_to_exact_y(sender, token_y, token_z, amount_out, sender_addr);
        } else {
            swap::swap_y_to_exact_x(sender, token_z, token_y, amount_out, sender_addr);
        };
    }
    
    // Multi-hop swap (3 hops)
    public entry fun swap_exact_input_triplehop(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        token_z: Object<Metadata>,
        token_a: Object<Metadata>,
        amount_in: u64,
        amount_out_min: u64
    ) {
        // Verify pairs exist
        assert!(is_pair_created(token_x, token_y), E_PAIR_NOT_CREATED);
        assert!(is_pair_created(token_y, token_z), E_PAIR_NOT_CREATED);
        assert!(is_pair_created(token_z, token_a), E_PAIR_NOT_CREATED);
        
        let sender_addr = signer::address_of(sender);
        
        // First hop: X -> Y
        let y_amount = if (swap_utils::compare_tokens(token_x, token_y) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_x, token_y, amount_in, sender_addr)
        } else {
            swap::swap_exact_y_to_x(sender, token_y, token_x, amount_in, sender_addr)
        };
        
        // Second hop: Y -> Z
        let z_amount = if (swap_utils::compare_tokens(token_y, token_z) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_y, token_z, y_amount, sender_addr)
        } else {
            swap::swap_exact_y_to_x(sender, token_z, token_y, y_amount, sender_addr)
        };
        
        // Third hop: Z -> A
        let a_amount = if (swap_utils::compare_tokens(token_z, token_a) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_z, token_a, z_amount, sender_addr)
        } else {
            swap::swap_exact_y_to_x(sender, token_a, token_z, z_amount, sender_addr)
        };
        
        assert!(a_amount >= amount_out_min, E_OUTPUT_LESS_THAN_MIN);
    }
    
    // Multi-hop swap (4 hops)
    public entry fun swap_exact_input_quadruplehop(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>,
        token_z: Object<Metadata>,
        token_a: Object<Metadata>,
        token_b: Object<Metadata>,
        amount_in: u64,
        amount_out_min: u64
    ) {
        // Verify pairs exist
        assert!(is_pair_created(token_x, token_y), E_PAIR_NOT_CREATED);
        assert!(is_pair_created(token_y, token_z), E_PAIR_NOT_CREATED);
        assert!(is_pair_created(token_z, token_a), E_PAIR_NOT_CREATED);
        assert!(is_pair_created(token_a, token_b), E_PAIR_NOT_CREATED);
        
        let sender_addr = signer::address_of(sender);
        
        // First hop: X -> Y
        let y_amount = if (swap_utils::compare_tokens(token_x, token_y) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_x, token_y, amount_in, sender_addr)
        } else {
            swap::swap_exact_y_to_x(sender, token_y, token_x, amount_in, sender_addr)
        };
        
        // Second hop: Y -> Z
        let z_amount = if (swap_utils::compare_tokens(token_y, token_z) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_y, token_z, y_amount, sender_addr)
        } else {
            swap::swap_exact_y_to_x(sender, token_z, token_y, y_amount, sender_addr)
        };
        
        // Third hop: Z -> A
        let a_amount = if (swap_utils::compare_tokens(token_z, token_a) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_z, token_a, z_amount, sender_addr)
        } else {
            swap::swap_exact_y_to_x(sender, token_a, token_z, z_amount, sender_addr)
        };
        
        // Fourth hop: A -> B
        let b_amount = if (swap_utils::compare_tokens(token_a, token_b) == swap_utils::get_smaller_enum()) {
            swap::swap_exact_x_to_y(sender, token_a, token_b, a_amount, sender_addr)
        } else {
            swap::swap_exact_y_to_x(sender, token_b, token_a, a_amount, sender_addr)
        };
        
        assert!(b_amount >= amount_out_min, E_OUTPUT_LESS_THAN_MIN);
    }
    
    // Helper functions
    
    // Register LP token
    public entry fun register_lp(
        sender: &signer,
        token_x: Object<Metadata>,
        token_y: Object<Metadata>
    ) {
        swap::register_lp(sender, token_x, token_y);
    }
    
    // Register for a token
    public entry fun register_token(
        sender: &signer,
        token: Object<Metadata>
    ) {
        primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender), token);
    }
}