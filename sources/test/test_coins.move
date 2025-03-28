#[test_only]
module test_coin::test_coins {
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, Metadata, MintRef, TransferRef, BurnRef};
    use aptos_framework::primary_fungible_store;
    use std::option;

    // Token type definitions
    struct TestWARP has drop {}
    struct TestBUSD has drop {}
    struct TestUSDC has drop {}
    struct TestBNB has drop {}
    struct TestAPT has drop {}

    // Resource to store mint capabilities
    struct TokenMintCapabilities has key {
        warp_mint_ref: MintRef,
        busd_mint_ref: MintRef,
        usdc_mint_ref: MintRef,
        bnb_mint_ref: MintRef,
        apt_mint_ref: MintRef,
        // Store token objects for easy reference
        warp_token: Object<Metadata>,
        busd_token: Object<Metadata>,
        usdc_token: Object<Metadata>,
        bnb_token: Object<Metadata>,
        apt_token: Object<Metadata>
    }

    public fun init_coins(): signer {
        let account = account::create_account_for_test(@test_coin);
        
        // Create WARP token
        let constructor_ref = object::create_named_object(&account, b"TestWARP");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            string::utf8(b"Warp Token"),
            string::utf8(b"WARP"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let warp_mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let warp_token = object::object_from_constructor_ref<Metadata>(&constructor_ref);
        
        // Create BUSD token
        let constructor_ref = object::create_named_object(&account, b"TestBUSD");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            string::utf8(b"BUSD Token"),
            string::utf8(b"BUSD"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let busd_mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let busd_token = object::object_from_constructor_ref<Metadata>(&constructor_ref);
        
        // Create USDC token
        let constructor_ref = object::create_named_object(&account, b"TestUSDC");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            string::utf8(b"USDC Token"),
            string::utf8(b"USDC"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let usdc_mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let usdc_token = object::object_from_constructor_ref<Metadata>(&constructor_ref);
        
        // Create BNB token
        let constructor_ref = object::create_named_object(&account, b"TestBNB");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            string::utf8(b"BNB Token"),
            string::utf8(b"BNB"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let bnb_mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let bnb_token = object::object_from_constructor_ref<Metadata>(&constructor_ref);
        
        // Create APT token
        let constructor_ref = object::create_named_object(&account, b"TestAPT");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            string::utf8(b"APT Token"),
            string::utf8(b"APT"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let apt_mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let apt_token = object::object_from_constructor_ref<Metadata>(&constructor_ref);
        
        // Store mint capabilities
        move_to(&account, TokenMintCapabilities {
            warp_mint_ref,
            busd_mint_ref,
            usdc_mint_ref,
            bnb_mint_ref,
            apt_mint_ref,
            warp_token,
            busd_token,
            usdc_token,
            bnb_token,
            apt_token
        });
        
        account
    }

    public fun get_token<T: drop>(): Object<Metadata> acquires TokenMintCapabilities {
        let caps = borrow_global<TokenMintCapabilities>(@test_coin);
        
        if (std::type_info::type_of<T>() == std::type_info::type_of<TestWARP>()) {
            caps.warp_token
        } else if (std::type_info::type_of<T>() == std::type_info::type_of<TestBUSD>()) {
            caps.busd_token
        } else if (std::type_info::type_of<T>() == std::type_info::type_of<TestUSDC>()) {
            caps.usdc_token
        } else if (std::type_info::type_of<T>() == std::type_info::type_of<TestBNB>()) {
            caps.bnb_token
        } else if (std::type_info::type_of<T>() == std::type_info::type_of<TestAPT>()) {
            caps.apt_token
        } else {
            abort 404
        }
    }

    public fun register_and_mint<T: drop>(coin_owner: &signer, to: &signer, amount: u64) acquires TokenMintCapabilities {
        let token = get_token<T>();
        
        // Register user for token
        primary_fungible_store::ensure_primary_store_exists(signer::address_of(to), token);
        
        // Mint tokens
        let caps = borrow_global<TokenMintCapabilities>(@test_coin);
        let mint_ref = if (std::type_info::type_of<T>() == std::type_info::type_of<TestWARP>()) {
            &caps.warp_mint_ref
        } else if (std::type_info::type_of<T>() == std::type_info::type_of<TestBUSD>()) {
            &caps.busd_mint_ref
        } else if (std::type_info::type_of<T>() == std::type_info::type_of<TestUSDC>()) {
            &caps.usdc_mint_ref
        } else if (std::type_info::type_of<T>() == std::type_info::type_of<TestBNB>()) {
            &caps.bnb_mint_ref
        } else if (std::type_info::type_of<T>() == std::type_info::type_of<TestAPT>()) {
            &caps.apt_mint_ref
        } else {
            abort 404
        };
        
        let fa = fungible_asset::mint(mint_ref, amount);
        primary_fungible_store::deposit(signer::address_of(to), fa);
    }

    public fun mint<T: drop>(coin_owner: &signer, to: &signer, amount: u64) acquires TokenMintCapabilities {
        register_and_mint<T>(coin_owner, to, amount);
    }
}