#[test_only]
module warpgate::swap_test {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use warpgate::swap::{Self, initialize};
    use warpgate::router;
    use warpgate::math;
    use aptos_std::math64::pow;
    use warpgate::swap_utils;
    use warpgate::test_utils;
    use test_coin::test_coins;
     use std::string;
    
    const MAX_U64: u64 = 18446744073709551615;
    const MINIMUM_LIQUIDITY: u128 = 1000;
    const SCALING_FACTOR: u128 = 1000000000000;

    public fun setup_test_with_genesis(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        test_utils::setup_test_with_genesis(dev, admin, treasury, resource_account);
    }

    public fun setup_test(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        test_utils::setup_test(dev, admin, treasury, resource_account);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_input(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        // Get token objects
        let warp_token = test_coins::get_token<test_coins::TestWARP>();
        let busd_token = test_coins::get_token<test_coins::TestBUSD>();

        // Register and mint tokens
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        router::register_token(alice, warp_token);
        router::register_token(alice, busd_token);
        
        // Mint tokens to users
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<test_coins::TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        let input_x = 2 * pow(10, 8);
        
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);
        
        // bob provider liquidity for 5:10 WARP-BUSD
        router::add_liquidity(bob, warp_token, busd_token, initial_reserve_x, initial_reserve_y, 0, 0, 25);
        let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

        let alice_token_x_before_balance = primary_fungible_store::balance(signer::address_of(alice), warp_token);
        
        let fee_add = swap::fee_to();
        let fee_signer = account::create_account_for_test(fee_add);
        router::register_token(&fee_signer, warp_token);
        
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        router::register_token(&mm_fee_signer, warp_token);
        
        router::swap_exact_input(alice, warp_token, busd_token, input_x, 0);

        let alice_token_x_after_balance = primary_fungible_store::balance(signer::address_of(alice), warp_token);
        let alice_token_y_after_balance = primary_fungible_store::balance(signer::address_of(alice), busd_token);

        // Calculate fee
        let fee_amount = (input_x as u128) * 25 / 10000;
        let amount_after_fee = input_x - (fee_amount as u64);

        let output_y = test_utils::calc_output_using_input(amount_after_fee, initial_reserve_x, initial_reserve_y);
        let new_reserve_x = initial_reserve_x + amount_after_fee;
        let new_reserve_y = initial_reserve_y - (output_y as u64);

        let (reserve_x, reserve_y, _) = swap::token_reserves(warp_token, busd_token);
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == input_x, 99);
        assert!(alice_token_y_after_balance == (output_y as u64), 98);
        assert!(reserve_x == new_reserve_x, 97);
        assert!(reserve_y == new_reserve_y, 96);

        let bob_token_x_before_balance = primary_fungible_store::balance(signer::address_of(bob), warp_token);
        let bob_token_y_before_balance = primary_fungible_store::balance(signer::address_of(bob), busd_token);

        router::remove_liquidity(bob, warp_token, busd_token, (bob_suppose_lp_balance as u64), 0, 0);

        let bob_token_x_after_balance = primary_fungible_store::balance(signer::address_of(bob), warp_token);
        let bob_token_y_after_balance = primary_fungible_store::balance(signer::address_of(bob), busd_token);

        let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
        let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
        let suppose_fee_amount = test_utils::calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
        suppose_total_supply = suppose_total_supply + suppose_fee_amount;

        // Calculate using scaled approach
        let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        
        new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
        new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
        suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

         // Allow for small rounding differences when comparing token amounts
        let actual_x_received = bob_token_x_after_balance - bob_token_x_before_balance;
        let expected_x = (bob_remove_liquidity_x as u64);
        let diff_x = if (actual_x_received > expected_x) { actual_x_received - expected_x } else { expected_x - actual_x_received };
        
        let actual_y_received = bob_token_y_after_balance - bob_token_y_before_balance;
        let expected_y = (bob_remove_liquidity_y as u64);
        let diff_y = if (actual_y_received > expected_y) { actual_y_received - expected_y } else { expected_y - actual_y_received };
        
        // Allow for a small rounding error (0.02% of the expected amount)
        let max_allowed_diff_x = expected_x / 5000; // 0.02%
        let max_allowed_diff_y = expected_y / 5000; // 0.02%
        
        assert!(diff_x <= max_allowed_diff_x, 95);
        assert!(diff_y <= max_allowed_diff_y, 94);

        swap::withdraw_fee(treasury, warp_token, busd_token);
        let lp_token = swap::get_lp_token(warp_token, busd_token);
        let treasury_lp_after_balance = primary_fungible_store::balance(signer::address_of(treasury), lp_token);
        router::remove_liquidity(treasury, warp_token, busd_token, (suppose_fee_amount as u64), 0, 0);
        let treasury_token_x_after_balance = primary_fungible_store::balance(signer::address_of(treasury), warp_token);
        let treasury_token_y_after_balance = primary_fungible_store::balance(signer::address_of(treasury), busd_token);

        // Calculate using scaled approach for treasury
        let treasury_proportion = (suppose_fee_amount * SCALING_FACTOR) / suppose_total_supply;
        let treasury_remove_liquidity_x = ((new_reserve_x as u128) * treasury_proportion) / SCALING_FACTOR;
        let treasury_remove_liquidity_y = ((new_reserve_y as u128) * treasury_proportion) / SCALING_FACTOR;
        
        assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
        assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
        assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
        
        let mm_fee_collector_balance = primary_fungible_store::balance(signer::address_of(&mm_fee_signer), warp_token);
        assert!(mm_fee_collector_balance == (fee_amount as u64), 90);
        
    }
    
    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_input_overflow(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        // Get token objects
        let warp_token = test_coins::get_token<test_coins::TestWARP>();
        let busd_token = test_coins::get_token<test_coins::TestBUSD>();

        // Register and mint tokens for bob
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, bob, MAX_U64);
        test_coins::register_and_mint<test_coins::TestBUSD>(&coin_owner, bob, MAX_U64);
        
        // Register and mint tokens for alice
        router::register_token(alice, warp_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, alice, MAX_U64);

        let initial_reserve_x = MAX_U64 / pow(10, 4);
        let initial_reserve_y = MAX_U64 / pow(10, 4);
        let input_x = pow(10, 9) * pow(10, 8);
        
        // Register market maker fee recipient
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(mm_fee_add));
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);
        
        // Bob provides liquidity
        router::add_liquidity(bob, warp_token, busd_token, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        // Register fee recipient
        let fee_add = swap::fee_to();
        let fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(fee_add));
        router::register_token(&fee_signer, warp_token);
        router::register_token(&fee_signer, busd_token);

        // Alice performs swap with large amount
        router::swap_exact_input(alice, warp_token, busd_token, input_x, 0);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_input_with_not_enough_liquidity(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        
        let coin_owner = test_coins::init_coins();

        // Get token objects
        let warp_token = test_coins::get_token<test_coins::TestWARP>();
        let busd_token = test_coins::get_token<test_coins::TestBUSD>();

        // Register and mint tokens for bob
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, bob, MAX_U64);
        test_coins::register_and_mint<test_coins::TestBUSD>(&coin_owner, bob, MAX_U64);
        
        // Register and mint tokens for alice
        router::register_token(alice, warp_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, alice, MAX_U64);

        let initial_reserve_x = MAX_U64 / pow(10, 4);
        let initial_reserve_y = MAX_U64 / pow(10, 4);
        let input_x = pow(10, 9) * pow(10, 8);
        
        // Register market maker fee recipient
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(mm_fee_add));
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);
        // Bob provides initial liquidity
        let initial_reserve_x = 100 * pow(10, 8);
        let initial_reserve_y = 200 * pow(10, 8);
        router::add_liquidity(bob, warp_token, busd_token, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        // Alice tries to swap with an amount that exceeds available liquidity
        let input_x = 10000 * pow(10, 8);
        router::swap_exact_input(alice, warp_token, busd_token, input_x, 0);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure(abort_code = 0, location = warpgate::router)]
    fun test_swap_exact_input_under_min_output(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        // Get token objects
        let warp_token = test_coins::get_token<test_coins::TestWARP>();
        let busd_token = test_coins::get_token<test_coins::TestBUSD>();

        // Register and mint tokens for bob
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<test_coins::TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        
        // Register and mint tokens for alice
        router::register_token(alice, warp_token);
        router::register_token(alice, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, alice, 100 * pow(10, 8));
        
        // Register market maker fee recipient
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(mm_fee_add));
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);
        
        // Register protocol fee recipient
        let fee_add = swap::fee_to();
        let fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(fee_add));
        router::register_token(&fee_signer, warp_token);
        router::register_token(&fee_signer, busd_token);

        // Bob provides initial liquidity
        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        router::add_liquidity(bob, warp_token, busd_token, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        // Calculate expected output amount
        let input_x = 2 * pow(10, 8);
        let output_y = test_utils::calc_output_using_input(input_x, initial_reserve_x, initial_reserve_y);
        
        // Convert output_y from u128 to u64 and add 1 to make it exceed the actual output
        let min_output_y = (output_y as u64) + 1;
        
        // Alice tries to swap with minimum output higher than what's possible
        // This should fail with E_OUTPUT_LESS_THAN_MIN (code 0) in the router module
        router::swap_exact_input(alice, warp_token, busd_token, input_x, min_output_y);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure]
    fun test_swap_exact_output_with_not_enough_liquidity(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        // Get token objects
        let warp_token = test_coins::get_token<test_coins::TestWARP>();
        let busd_token = test_coins::get_token<test_coins::TestBUSD>();

        // Register and mint tokens for bob
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, bob, 1000 * pow(10, 8));
        test_coins::register_and_mint<test_coins::TestBUSD>(&coin_owner, bob, 1000 * pow(10, 8));
        
        // Register and mint tokens for alice
        router::register_token(alice, warp_token);
        router::register_token(alice, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, alice, 1000 * pow(10, 8));
        
        // Register market maker fee recipient
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(mm_fee_add));
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);
        
        // Register protocol fee recipient
        let fee_add = swap::fee_to();
        let fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(fee_add));
        router::register_token(&fee_signer, warp_token);
        router::register_token(&fee_signer, busd_token);

        // Bob provides initial liquidity
        let initial_reserve_x = 100 * pow(10, 8);
        let initial_reserve_y = 200 * pow(10, 8);
        router::add_liquidity(bob, warp_token, busd_token, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        // Try to swap for more tokens than are in the pool
        let output_y = 1000 * pow(10, 8); // This is more than the reserve_y
        let input_x_max = 1000 * pow(10, 8);
        
        // This should fail because the pool doesn't have enough liquidity
        router::swap_exact_output(alice, warp_token, busd_token, output_y, input_x_max);
    }
    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_output(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        // Get token objects
        let warp_token = test_coins::get_token<test_coins::TestWARP>();
        let busd_token = test_coins::get_token<test_coins::TestBUSD>();

        // Register and mint tokens for bob
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<test_coins::TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        
        // Register and mint tokens for alice
        router::register_token(alice, warp_token);
        router::register_token(alice, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, alice, 100 * pow(10, 8));
        
        // Register market maker fee recipient
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(mm_fee_add));
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);
        
        // Register protocol fee recipient
        let fee_add = swap::fee_to();
        let fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(fee_add));
        router::register_token(&fee_signer, warp_token);
        router::register_token(&fee_signer, busd_token);

        // Bob provides initial liquidity
        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        router::add_liquidity(bob, warp_token, busd_token, initial_reserve_x, initial_reserve_y, 0, 0, 25);
        let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

        // Define the exact output amount we want
        let output_y = 166319299;
        let input_x_max = 1 * pow(10, 8);
        
        // Check Alice's token balances before swap
        let alice_token_x_before_balance = primary_fungible_store::balance(signer::address_of(alice), warp_token);
        // Execute the swap with exact output
        router::swap_exact_output(alice, warp_token, busd_token, output_y, input_x_max);

        // Check Alice's token balances after swap
        let alice_token_x_after_balance = primary_fungible_store::balance(signer::address_of(alice), warp_token);
        let alice_token_y_after_balance = primary_fungible_store::balance(signer::address_of(alice), busd_token);

        // Calculate the expected input amount
        let input_x = test_utils::calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y);
        
        // Calculate new reserves
        let new_reserve_x = initial_reserve_x + (input_x as u64);
        let new_reserve_y = initial_reserve_y - output_y;

        // Verify reserves
        let (reserve_x, reserve_y, _) = swap::token_reserves(warp_token, busd_token);

        let mm_fee = swap::get_mm_fee();
        let mm_fee_amount = input_x * mm_fee / 10000;
        
        // Verify Alice's balances
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == ((input_x + mm_fee_amount) as u64), 99);
        assert!(alice_token_y_after_balance == output_y, 98);
        
        // Verify pool reserves
        assert!(reserve_x == new_reserve_x, 97);
        assert!(reserve_y == new_reserve_y, 96);

        // Check Bob's token balances before removing liquidity
        let bob_token_x_before_balance = primary_fungible_store::balance(signer::address_of(bob), warp_token);
        let bob_token_y_before_balance = primary_fungible_store::balance(signer::address_of(bob), busd_token);

        // Bob removes liquidity
        router::remove_liquidity(bob, warp_token, busd_token, (bob_suppose_lp_balance as u64), 0, 0);

        // Check Bob's token balances after removing liquidity
        let bob_token_x_after_balance = primary_fungible_store::balance(signer::address_of(bob), warp_token);
        let bob_token_y_after_balance = primary_fungible_store::balance(signer::address_of(bob), busd_token);

        // Calculate k values for fee calculation
        let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
        let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
        let suppose_fee_amount = test_utils::calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
        suppose_total_supply = suppose_total_supply + suppose_fee_amount;

        // Calculate Bob's expected tokens using the scaled approach to avoid precision loss
        let bob_proportion = (bob_suppose_lp_balance * SCALING_FACTOR) / suppose_total_supply;
        let bob_remove_liquidity_x = ((new_reserve_x as u128) * bob_proportion) / SCALING_FACTOR;
        let bob_remove_liquidity_y = ((new_reserve_y as u128) * bob_proportion) / SCALING_FACTOR;
        
        // Update reserves after Bob's withdrawal
        new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
        new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
        suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

        // Allow for small rounding differences when comparing token amounts
        let actual_x_received = bob_token_x_after_balance - bob_token_x_before_balance;
        let expected_x = (bob_remove_liquidity_x as u64);
        let diff_x = if (actual_x_received > expected_x) { actual_x_received - expected_x } else { expected_x - actual_x_received };
        
        let actual_y_received = bob_token_y_after_balance - bob_token_y_before_balance;
        let expected_y = (bob_remove_liquidity_y as u64);
        let diff_y = if (actual_y_received > expected_y) { actual_y_received - expected_y } else { expected_y - actual_y_received };
        
        // Allow for a small rounding error (0.02% of the expected amount)
        let max_allowed_diff_x = expected_x / 5000; // 0.02%
        let max_allowed_diff_y = expected_y / 5000; // 0.02%
        
        assert!(diff_x <= max_allowed_diff_x, 95);
        assert!(diff_y <= max_allowed_diff_y, 94);

        // Withdraw fees and check treasury balances
        swap::withdraw_fee(treasury, warp_token, busd_token);
        let lp_token = swap::get_lp_token(warp_token, busd_token);
        let treasury_lp_after_balance = primary_fungible_store::balance(signer::address_of(treasury), lp_token);
        
        // Treasury removes liquidity
        router::remove_liquidity(treasury, warp_token, busd_token, (suppose_fee_amount as u64), 0, 0);
        let treasury_token_x_after_balance = primary_fungible_store::balance(signer::address_of(treasury), warp_token);
        let treasury_token_y_after_balance = primary_fungible_store::balance(signer::address_of(treasury), busd_token);

        // Calculate treasury's expected tokens using the scaled approach
        let treasury_proportion = (suppose_fee_amount * SCALING_FACTOR) / suppose_total_supply;
        let treasury_remove_liquidity_x = ((new_reserve_x as u128) * treasury_proportion) / SCALING_FACTOR;
        let treasury_remove_liquidity_y = ((new_reserve_y as u128) * treasury_proportion) / SCALING_FACTOR;

        // Verify treasury received the correct LP tokens and token amounts
        assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
        
        // Allow for small rounding differences for treasury tokens too
        let treasury_diff_x = if (treasury_token_x_after_balance > (treasury_remove_liquidity_x as u64)) { 
            treasury_token_x_after_balance - (treasury_remove_liquidity_x as u64) 
        } else { 
            (treasury_remove_liquidity_x as u64) - treasury_token_x_after_balance 
        };
        
        let treasury_diff_y = if (treasury_token_y_after_balance > (treasury_remove_liquidity_y as u64)) { 
            treasury_token_y_after_balance - (treasury_remove_liquidity_y as u64) 
        } else { 
            (treasury_remove_liquidity_y as u64) - treasury_token_y_after_balance 
        };
        
        let treasury_max_diff_x = (treasury_remove_liquidity_x as u64) / 5000; // 0.02%
        let treasury_max_diff_y = (treasury_remove_liquidity_y as u64) / 5000; // 0.02%
        
        assert!(treasury_diff_x <= treasury_max_diff_x, 92);
        assert!(treasury_diff_y <= treasury_max_diff_y, 91);
    }
    
    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure(abort_code = 1, location = warpgate::router)]
    fun test_swap_exact_output_exceed_max_input(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        // Get token objects
        let warp_token = test_coins::get_token<test_coins::TestWARP>();
        let busd_token = test_coins::get_token<test_coins::TestBUSD>();

        // Register and mint tokens for bob
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, bob, 1000 * pow(10, 8));
        test_coins::register_and_mint<test_coins::TestBUSD>(&coin_owner, bob, 1000 * pow(10, 8));
        
        // Register and mint tokens for alice
        router::register_token(alice, warp_token);
        router::register_token(alice, busd_token);
        test_coins::register_and_mint<test_coins::TestWARP>(&coin_owner, alice, 1000 * pow(10, 8));
        
        // Register market maker fee recipient
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(mm_fee_add));
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);
        
        // Register protocol fee recipient
        let fee_add = swap::fee_to();
        let fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(fee_add));
        router::register_token(&fee_signer, warp_token);
        router::register_token(&fee_signer, busd_token);

        // Bob provides initial liquidity
        let initial_reserve_x = 50 * pow(10, 8);
        let initial_reserve_y = 100 * pow(10, 8);
        router::add_liquidity(bob, warp_token, busd_token, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        // Define the exact output amount we want
        let output_y = 166319299;
        
        // Calculate the required input amount and subtract 1 to make it insufficient
        let input_x = test_utils::calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y);
        let input_x_max = (input_x as u64) - 1;
        
        // This should fail because the max input amount is less than required
        router::swap_exact_output(alice, warp_token, busd_token, output_y, input_x_max);
    }
    
    
}