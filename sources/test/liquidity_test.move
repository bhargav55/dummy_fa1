
#[test_only]
module warpgate::liquidity_test {
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef};
    use aptos_framework::primary_fungible_store;
    use warpgate::swap::{Self, initialize};
    use warpgate::router;
    use warpgate::math;
    use warpgate::test_utils;

    const MINIMUM_LIQUIDITY: u128 = 1000;
    const MM_FEE_ADDRESS: address = @mmfee;

    // Resource to store mint capabilities
    struct MintCapStore has key {
        warp_mint_ref: MintRef,
        busd_mint_ref: MintRef
    }

    // Structure to hold token objects
    struct Tokens has copy, drop {
        warp_token: Object<Metadata>,
        busd_token: Object<Metadata>
    }

    // Initialize test tokens for FA model and return token objects
    fun init_test_tokens(creator: &signer): Tokens {
        // Create WARP token
        let constructor_ref = object::create_named_object(creator, b"TestWARP");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            std::option::none(),
            string::utf8(b"Warp Token"),
            string::utf8(b"WARP"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let warp_token = object::object_from_constructor_ref<Metadata>(&constructor_ref);
        let warp_mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);

        // Create BUSD token
        let constructor_ref = object::create_named_object(creator, b"TestBUSD");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            std::option::none(),
            string::utf8(b"BUSD Token"),
            string::utf8(b"BUSD"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let busd_token = object::object_from_constructor_ref<Metadata>(&constructor_ref);
        let busd_mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);

        // Store mint capabilities in creator's account
        move_to(creator, MintCapStore {
            warp_mint_ref,
            busd_mint_ref
        });

        Tokens {
            warp_token,
            busd_token
        }
    }

    // Mint tokens to a user using stored mint capabilities
    fun mint_tokens(
        creator_addr: address, 
        user: &signer, 
        token: Object<Metadata>, 
        amount: u64
    ) acquires MintCapStore {
        // Get stored mint capability
        let cap_store = borrow_global<MintCapStore>(creator_addr);
        
        // Ensure user has a store
        primary_fungible_store::ensure_primary_store_exists(signer::address_of(user), token);
        
        // Determine which token we're minting and mint accordingly
        let token_fa = if (fungible_asset::symbol(token) == string::utf8(b"WARP")) {
            fungible_asset::mint(&cap_store.warp_mint_ref, amount)
        } else if (fungible_asset::symbol(token) == string::utf8(b"BUSD")) {
            fungible_asset::mint(&cap_store.busd_mint_ref, amount)
        } else {
            abort 404
        };
        
        // Deposit to user
        primary_fungible_store::deposit(signer::address_of(user), token_fa);
    }
    
    // Create power function for 10^n
    fun pow(n: u64): u64 {
        let result = 1u64;
        let i = 0;
        while (i < n) {
            result = result * 10;
            i = i + 1;
        };
        result
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_add_liquidity(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) acquires MintCapStore {
        // Initialize test accounts if they don't exist
        if (!account::exists_at(signer::address_of(bob))) {
            account::create_account_for_test(signer::address_of(bob));
        };
        if (!account::exists_at(signer::address_of(alice))) {
            account::create_account_for_test(signer::address_of(alice));
        };
        if (!account::exists_at(signer::address_of(dev))) {
            account::create_account_for_test(signer::address_of(dev));
        };
        if (!account::exists_at(signer::address_of(admin))) {
            account::create_account_for_test(signer::address_of(admin));
        };
        if (!account::exists_at(signer::address_of(treasury))) {
            account::create_account_for_test(signer::address_of(treasury));
        };
        if (!account::exists_at(@lpfee)) {
            account::create_account_for_test(@lpfee);
        };
        if (!account::exists_at(@mmfee)) {
            account::create_account_for_test(@mmfee);
        };
        test_utils::setup_test_with_genesis(dev, admin, treasury, resource_account);

        

        // Create token creator account if it doesn't exist
        if (!account::exists_at(@default_admin)) {
            account::create_account_for_test(@default_admin);
        };
        let token_creator = account::create_signer_with_capability(&account::create_test_signer_cap(@default_admin));
        let tokens = init_test_tokens(&token_creator);
        
        let warp_token = tokens.warp_token;
        let busd_token = tokens.busd_token;

        // Register and mint tokens
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        router::register_token(alice, warp_token);
        router::register_token(alice, busd_token);
        
        // Mint tokens to users
        mint_tokens(@default_admin, bob, warp_token, 100 * pow(10));
        mint_tokens(@default_admin, bob, busd_token, 100 * pow(10));
        mint_tokens(@default_admin, alice, warp_token, 100 * pow(10));
        mint_tokens(@default_admin, alice, busd_token, 100 * pow(10));

        let bob_liquidity_x = 5 * pow(10);
        let bob_liquidity_y = 10 * pow(10);
        let alice_liquidity_x = 2 * pow(10);
        let alice_liquidity_y = 4 * pow(10);

        // Register MM fee recipient for tokens if not already registered
        let mm_fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(MM_FEE_ADDRESS));
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);
 
        // Bob provides liquidity first
        router::add_liquidity(bob, warp_token, busd_token, bob_liquidity_x, bob_liquidity_y, 0, 0, 25);
        
        // Alice provides liquidity second
        router::add_liquidity(alice, warp_token, busd_token, alice_liquidity_x, alice_liquidity_y, 0, 0, 25);

        // Get balances and reserves
        let (reserve_x, reserve_y, _) = swap::token_reserves(warp_token, busd_token);
        let lp_token = swap::get_lp_token(warp_token, busd_token);
        
        // Check LP balances
        let bob_lp_balance = primary_fungible_store::balance(signer::address_of(bob), lp_token);
        let alice_lp_balance = primary_fungible_store::balance(signer::address_of(alice), lp_token);
        //let resource_account_lp_balance = primary_fungible_store::balance(object::object_address(&lp_token), lp_token);
        let resource_account_lp_balance = primary_fungible_store::balance(@warpgate, lp_token);
        
        // Calculate expected values
        let resource_account_suppose_lp_balance = MINIMUM_LIQUIDITY;
        let bob_suppose_lp_balance = math::sqrt(((bob_liquidity_x as u128) * (bob_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
        let total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
        let alice_suppose_lp_balance = math::min(
            (alice_liquidity_x as u128) * total_supply / (bob_liquidity_x as u128), 
            (alice_liquidity_y as u128) * total_supply / (bob_liquidity_y as u128)
        );

        // Assertions
        assert!(reserve_x == bob_liquidity_x + alice_liquidity_x, 99);
        assert!(reserve_y == bob_liquidity_y + alice_liquidity_y, 97);
        

        assert!(bob_lp_balance == (bob_suppose_lp_balance as u64), 95);
        assert!(alice_lp_balance == (alice_suppose_lp_balance as u64), 94);
       
        assert!(resource_account_lp_balance == (resource_account_suppose_lp_balance as u64), 93);
    }
   
    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_add_liquidity_with_less_x_ratio(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) acquires MintCapStore {
        // Initialize test accounts if they don't exist
        if (!account::exists_at(signer::address_of(bob))) {
            account::create_account_for_test(signer::address_of(bob));
        };
        if (!account::exists_at(signer::address_of(alice))) {
            account::create_account_for_test(signer::address_of(alice));
        };
        if (!account::exists_at(signer::address_of(dev))) {
            account::create_account_for_test(signer::address_of(dev));
        };
        if (!account::exists_at(signer::address_of(admin))) {
            account::create_account_for_test(signer::address_of(admin));
        };
        if (!account::exists_at(signer::address_of(treasury))) {
            account::create_account_for_test(signer::address_of(treasury));
        };
        if (!account::exists_at(@lpfee)) {
            account::create_account_for_test(@lpfee);
        };
        if (!account::exists_at(@mmfee)) {
            account::create_account_for_test(@mmfee);
        };
        
        test_utils::setup_test_with_genesis(dev, admin, treasury, resource_account);

        // Create token creator account if it doesn't exist
        if (!account::exists_at(@default_admin)) {
            account::create_account_for_test(@default_admin);
        };
        let token_creator = account::create_signer_with_capability(&account::create_test_signer_cap(@default_admin));
        let tokens = init_test_tokens(&token_creator);
        
        let warp_token = tokens.warp_token;
        let busd_token = tokens.busd_token;

        // Register and mint tokens
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        
        // Mint tokens to users
        mint_tokens(@default_admin, bob, warp_token, 200 * pow(10));
        mint_tokens(@default_admin, bob, busd_token, 200 * pow(10));

        let bob_liquidity_x = 5 * pow(10);
        let bob_liquidity_y = 10 * pow(10);

        // Register MM fee recipient for tokens if not already registered
        let mm_fee_signer = account::create_signer_with_capability(&account::create_test_signer_cap(MM_FEE_ADDRESS));
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);

        // Bob provides initial liquidity
        router::add_liquidity(bob, warp_token, busd_token, bob_liquidity_x, bob_liquidity_y, 0, 0, 25);

        let bob_token_x_before_balance = primary_fungible_store::balance(signer::address_of(bob), warp_token);
        let bob_token_y_before_balance = primary_fungible_store::balance(signer::address_of(bob), busd_token);

        // Add more liquidity with less X ratio
        let bob_add_liquidity_x = 1 * pow(10);
        let bob_add_liquidity_y = 5 * pow(10);
        router::add_liquidity(bob, warp_token, busd_token, bob_add_liquidity_x, bob_add_liquidity_y, 0, 0, 25);

        // Calculate expected liquidity
        let bob_added_liquidity_x = bob_add_liquidity_x;
        let bob_added_liquidity_y = (bob_add_liquidity_x as u128) * (bob_liquidity_y as u128) / (bob_liquidity_x as u128);

        // Get balances after adding liquidity
        let bob_token_x_after_balance = primary_fungible_store::balance(signer::address_of(bob), warp_token);
        let bob_token_y_after_balance = primary_fungible_store::balance(signer::address_of(bob), busd_token);

        // Get LP balance
        let lp_token = swap::get_lp_token(warp_token, busd_token);
        let bob_lp_balance = primary_fungible_store::balance(signer::address_of(bob), lp_token);
        let resource_account_lp_balance = primary_fungible_store::balance(@warpgate, lp_token);

        // Calculate expected values
        let resource_account_suppose_lp_balance = MINIMUM_LIQUIDITY;
        let bob_suppose_lp_balance = math::sqrt(((bob_liquidity_x as u128) * (bob_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
        let total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
        
        // Calculate the expected LP tokens for the second deposit
        let second_deposit_lp = math::min(
            (bob_add_liquidity_x as u128) * total_supply / (bob_liquidity_x as u128), 
            (bob_add_liquidity_y as u128) * total_supply / (bob_liquidity_y as u128)
        );
        
        bob_suppose_lp_balance = bob_suppose_lp_balance + second_deposit_lp;

        // Assertions
        assert!((bob_token_x_before_balance - bob_token_x_after_balance) == bob_added_liquidity_x, 99);
        assert!((bob_token_y_before_balance - bob_token_y_after_balance) == (bob_added_liquidity_y as u64), 98);
        assert!(bob_lp_balance == (bob_suppose_lp_balance as u64), 97);
        assert!(resource_account_lp_balance == (resource_account_suppose_lp_balance as u64), 96);
    }
    

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure(abort_code = 3, location = warpgate::router)]
    fun test_add_liquidity_with_less_x_ratio_and_less_than_y_min(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) acquires MintCapStore {
        // Initialize test accounts if they don't exist
        if (!account::exists_at(signer::address_of(bob))) {
            account::create_account_for_test(signer::address_of(bob));
        };
        if (!account::exists_at(signer::address_of(alice))) {
            account::create_account_for_test(signer::address_of(alice));
        };
        if (!account::exists_at(signer::address_of(dev))) {
            account::create_account_for_test(signer::address_of(dev));
        };
        if (!account::exists_at(signer::address_of(admin))) {
            account::create_account_for_test(signer::address_of(admin));
        };
        if (!account::exists_at(signer::address_of(treasury))) {
            account::create_account_for_test(signer::address_of(treasury));
        };
        if (!account::exists_at(@lpfee)) {
            account::create_account_for_test(@lpfee);
        };
        if (!account::exists_at(@mmfee)) {
            account::create_account_for_test(@mmfee);
        };
        

        test_utils::setup_test_with_genesis(dev, admin, treasury, resource_account);


        // Create token creator account if it doesn't exist
        if (!account::exists_at(@default_admin)) {
            account::create_account_for_test(@default_admin);
        };
        let token_creator = account::create_signer_with_capability(&account::create_test_signer_cap(@default_admin));
        let tokens = init_test_tokens(&token_creator);
        
        let warp_token = tokens.warp_token;
        let busd_token = tokens.busd_token;

        // Register and mint tokens
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        
        // Mint tokens to users
        mint_tokens(@default_admin, bob, warp_token, 200 * pow(10));
        mint_tokens(@default_admin, bob, busd_token, 200 * pow(10));

        let initial_reserve_x = 5 * pow(10);
        let initial_reserve_y = 10 * pow(10);

        // Register MM fee recipient
        let mm_fee_signer = account::create_account_for_test(MM_FEE_ADDRESS);
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);

        // Bob provides initial liquidity
        router::add_liquidity(bob, warp_token, busd_token, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        // Add more liquidity with too high y_min requirement
        let bob_add_liquidity_x = 1 * pow(10);
        let bob_add_liquidity_y = 5 * pow(10);
        
        // This should fail due to insufficient Y amount
        router::add_liquidity(bob, warp_token, busd_token, bob_add_liquidity_x, bob_add_liquidity_y, 0, 4 * pow(10), 25);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12341, alice = @0x12342)]
    fun test_remove_liquidity(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) acquires MintCapStore {
       // Initialize test accounts if they don't exist
        if (!account::exists_at(signer::address_of(bob))) {
            account::create_account_for_test(signer::address_of(bob));
        };
        if (!account::exists_at(signer::address_of(alice))) {
            account::create_account_for_test(signer::address_of(alice));
        };
        if (!account::exists_at(signer::address_of(dev))) {
            account::create_account_for_test(signer::address_of(dev));
        };
        if (!account::exists_at(signer::address_of(admin))) {
            account::create_account_for_test(signer::address_of(admin));
        };
        if (!account::exists_at(signer::address_of(treasury))) {
            account::create_account_for_test(signer::address_of(treasury));
        };
        if (!account::exists_at(@lpfee)) {
            account::create_account_for_test(@lpfee);
        };
        if (!account::exists_at(@mmfee)) {
            account::create_account_for_test(@mmfee);
        };
        
        test_utils::setup_test_with_genesis(dev, admin, treasury, resource_account);

        if (!account::exists_at(@default_admin)) {
            account::create_account_for_test(@default_admin);
        };
        let token_creator = account::create_signer_with_capability(&account::create_test_signer_cap(@default_admin));
        let tokens = init_test_tokens(&token_creator);
        
        let warp_token = tokens.warp_token;
        let busd_token = tokens.busd_token;

        // Register tokens
        router::register_token(bob, warp_token);
        router::register_token(bob, busd_token);
        router::register_token(alice, warp_token);
        router::register_token(alice, busd_token);
        
        // Mint tokens
        mint_tokens(@default_admin, bob, warp_token, 100 * pow(10));
        mint_tokens(@default_admin, bob, busd_token, 100 * pow(10));
        mint_tokens(@default_admin, alice, warp_token, 100 * pow(10));
        mint_tokens(@default_admin, alice, busd_token, 100 * pow(10));

        let bob_add_liquidity_x = 5 * pow(10);
        let bob_add_liquidity_y = 10 * pow(10);
        let alice_add_liquidity_x = 2 * pow(10);
        let alice_add_liquidity_y = 4 * pow(10);

        // Register MM fee recipient
        let mm_fee_signer = account::create_account_for_test(MM_FEE_ADDRESS);
        router::register_token(&mm_fee_signer, warp_token);
        router::register_token(&mm_fee_signer, busd_token);

        // Add liquidity
        router::add_liquidity(bob, warp_token, busd_token, bob_add_liquidity_x, bob_add_liquidity_y, 0, 0, 25);
        router::add_liquidity(alice, warp_token, busd_token, alice_add_liquidity_x, alice_add_liquidity_y, 0, 0, 25);

        // Calculate expected LP tokens
        let bob_suppose_lp_balance = math::sqrt(((bob_add_liquidity_x as u128) * (bob_add_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
        let alice_suppose_lp_balance = math::min(
            (alice_add_liquidity_x as u128) * suppose_total_supply / (bob_add_liquidity_x as u128), 
            (alice_add_liquidity_y as u128) * suppose_total_supply / (bob_add_liquidity_y as u128)
        );
        suppose_total_supply = suppose_total_supply + alice_suppose_lp_balance;
        let total_supply = swap::total_lp_supply(warp_token, busd_token);
        let lp_token = swap::get_lp_token(warp_token, busd_token);

        let resource_account_lp_balance = primary_fungible_store::balance(@warpgate, lp_token);


        let suppose_reserve_x = bob_add_liquidity_x + alice_add_liquidity_x;
        let suppose_reserve_y = bob_add_liquidity_y + alice_add_liquidity_y;

        // Get LP token and balances
        //let lp_token = swap::get_lp_token(warp_token, busd_token);
        let bob_lp_balance = primary_fungible_store::balance(signer::address_of(bob), lp_token);
        let alice_lp_balance = primary_fungible_store::balance(signer::address_of(alice), lp_token);

        assert!((bob_suppose_lp_balance as u64) == bob_lp_balance, 99);
        assert!((alice_suppose_lp_balance as u64) == alice_lp_balance, 98);
        // Check balances before removing liquidity
        let alice_token_x_before_balance = primary_fungible_store::balance(signer::address_of(alice), warp_token);
        let alice_token_y_before_balance = primary_fungible_store::balance(signer::address_of(alice), busd_token);
        let bob_token_x_before_balance = primary_fungible_store::balance(signer::address_of(bob), warp_token);
        let bob_token_y_before_balance = primary_fungible_store::balance(signer::address_of(bob), busd_token);
        // Remove liquidity
        router::remove_liquidity(bob, warp_token, busd_token, (bob_suppose_lp_balance as u64), 0, 0);
        // Calculate expected token returns
        let bob_remove_liquidity_x = ((suppose_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        let bob_remove_liquidity_y = ((suppose_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;
        suppose_reserve_x = suppose_reserve_x - (bob_remove_liquidity_x as u64);
        suppose_reserve_y = suppose_reserve_y - (bob_remove_liquidity_y as u64);

        // Remove Alice's liquidity
        router::remove_liquidity(alice, warp_token, busd_token, (alice_suppose_lp_balance as u64), 0, 0);
        
        // Calculate expected token returns
        let alice_remove_liquidity_x = ((suppose_reserve_x) as u128) * alice_suppose_lp_balance / suppose_total_supply;
        let alice_remove_liquidity_y = ((suppose_reserve_y) as u128) * alice_suppose_lp_balance / suppose_total_supply;
        suppose_reserve_x = suppose_reserve_x - (alice_remove_liquidity_x as u64);
        suppose_reserve_y = suppose_reserve_y - (alice_remove_liquidity_y as u64);

        // Check final balances
        let alice_lp_after_balance = primary_fungible_store::balance(signer::address_of(alice), lp_token);
        let bob_lp_after_balance = primary_fungible_store::balance(signer::address_of(bob), lp_token);
        let alice_token_x_after_balance = primary_fungible_store::balance(signer::address_of(alice), warp_token);
        let alice_token_y_after_balance = primary_fungible_store::balance(signer::address_of(alice), busd_token);
        let bob_token_x_after_balance = primary_fungible_store::balance(signer::address_of(bob), warp_token);
        let bob_token_y_after_balance = primary_fungible_store::balance(signer::address_of(bob), busd_token);
        
        // Get pool reserves
        let (reserve_x, reserve_y, _) = swap::token_reserves(warp_token, busd_token);
        let total_supply = swap::total_lp_supply(warp_token, busd_token);

        // Assertions
        assert!((alice_token_x_after_balance - alice_token_x_before_balance) == (alice_remove_liquidity_x as u64), 97);
        assert!((alice_token_y_after_balance - alice_token_y_before_balance) == (alice_remove_liquidity_y as u64), 96);
        assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
        assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);
        assert!(alice_lp_after_balance == 0, 93);
        assert!(bob_lp_after_balance == 0, 92);
        assert!(reserve_x == suppose_reserve_x, 89);
        assert!(reserve_y == suppose_reserve_y, 88);
        assert!(total_supply == MINIMUM_LIQUIDITY, 87);
    }
    
    
}
