// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/ZuniswapV2Factory.sol";
import "../src/ZuniswapV2Pair.sol";
import "../src/ZuniswapV2Router.sol";
import "./mock/ERC20Mintable.sol";

contract ZuniswapV2RouterTest is Test {
    ZuniswapV2Factory factory;
    ZuniswapV2Router router;

    ERC20Mintable tokenA;
    ERC20Mintable tokenB;
    ERC20Mintable tokenC;

    function setUp() public {
        factory = new ZuniswapV2Factory();
        router = new ZuniswapV2Router(address(factory));

        tokenA = new ERC20Mintable("Token A", "TKNA");
        tokenB = new ERC20Mintable("Token B", "TKNB");
        tokenC = new ERC20Mintable("Token C", "TKNC");

        tokenA.mint(address(this), 20 ether);
        tokenB.mint(address(this), 20 ether);
        tokenC.mint(address(this), 20 ether);
    }

    function encodeError(
        string memory error
    ) internal pure returns (bytes memory encoded) {
        encoded = abi.encodeWithSignature(error);
    }

    function testAddLiquidityNoPair() public {
        tokenA.approve(address(router), 1 ether);
        tokenB.approve(address(router), 1 ether);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = router
            .addLiquidity(
                address(tokenA),
                address(tokenB),
                1 ether,
                1 ether,
                1 ether,
                1 ether,
                address(this)
            );

        assertEq(amountA, 1 ether);
        assertEq(amountB, 1 ether);
        assertEq(liquidity, 1 ether - 1000);

        address pairAddress = factory.pairs(address(tokenA), address(tokenB));
        assertEq(tokenA.balanceOf(pairAddress), 1 ether);
        assertEq(tokenB.balanceOf(pairAddress), 1 ether);

        ZuniswapV2Pair pair = ZuniswapV2Pair(pairAddress);
        assertEq(pair.token0(), address(tokenB));
        assertEq(pair.token1(), address(tokenA));

        assertEq(pair.totalSupply(), 1 ether);
        assertEq(pair.balanceOf(address(this)), 1 ether - 1000);
        assertEq(tokenA.balanceOf(address(this)), 19 ether);
        assertEq(tokenB.balanceOf(address(this)), 19 ether);
    }

    function testAddliquidityAmountBoptimalIsOk() public {
        address pairAddress = factory.createPair(
            address(tokenA),
            address(tokenB)
        );
        ZuniswapV2Pair pair = ZuniswapV2Pair(pairAddress);

        assertEq(pair.token0(), address(tokenB));
        assertEq(pair.token1(), address(tokenA));

        tokenA.transfer(pairAddress, 1 ether);
        tokenB.transfer(pairAddress, 2 ether);
        pair.mint(address(this));

        tokenA.approve(address(router), 1 ether);
        tokenB.approve(address(router), 2 ether);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = router
            .addLiquidity(
                address(tokenA),
                address(tokenB),
                1 ether,
                2 ether,
                1 ether,
                1.9 ether,
                address(this)
            );

        assertEq(amountA, 1 ether);
        assertEq(amountB, 2 ether);
        assertEq(liquidity, 1414213562373095048);
    }

    function testRemoveLiquidity() public {
        address pairAddress = factory.createPair(
            address(tokenA),
            address(tokenB)
        );
        console.log(
            tokenA.balanceOf(address(this)),
            tokenB.balanceOf(address(this))
        );
        tokenA.approve(address(router), 1 ether);
        tokenB.approve(address(router), 2 ether);
        (uint256 amountA, uint256 amountB, uint256 liquidity) = router
            .addLiquidity(
                address(tokenA),
                address(tokenB),
                1 ether,
                2 ether,
                1 ether,
                1 ether,
                address(this)
            );

        assertEq(amountA, 1 ether);
        assertEq(amountB, 2 ether);
        // assertEq(liquidity, 1414213562373095048);
        // assertEq(
        //     ZuniswapV2Pair(pairAddress).totalSupply(),
        //     1414213562373095048
        // );
        ZuniswapV2Pair(pairAddress).approve(address(router), liquidity);
        (uint256 amountA_r, uint256 amountB_r) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            1 ether,
            1 ether,
            address(this)
        );

        assertEq(tokenA.balanceOf(address(this)), 20 ether);
        assertEq(tokenB.balanceOf(address(this)), 20 ether);
    }

    function testSwapExactTokensForTokens() public {
        tokenA.approve(address(router), 1 ether);
        tokenB.approve(address(router), 2 ether);
        tokenC.approve(address(router), 1 ether);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this)
        );

        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this)
        );

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        tokenA.approve(address(router), 0.3 ether);
        router.swapExactTokensForTokens(
            0.3 ether,
            0.1 ether,
            path,
            address(this)
        );

        // Swap 0.3 TKNA for ~0.186 TKNB
        assertEq(
            tokenA.balanceOf(address(this)),
            20 ether - 1 ether - 0.3 ether
        );
        assertEq(tokenB.balanceOf(address(this)), 20 ether - 2 ether);
        assertEq(
            tokenC.balanceOf(address(this)),
            20 ether - 1 ether + 0.186691414219734305 ether
        );
    }

    function testSwapTokensForExactTokens() public {
        tokenA.approve(address(router), 1 ether);
        tokenB.approve(address(router), 2 ether);
        tokenC.approve(address(router), 1 ether);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this)
        );

        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            1 ether,
            1 ether,
            1 ether,
            1 ether,
            address(this)
        );

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        tokenA.approve(address(router), 0.3 ether);
        router.swapTokensForExactTokens(
            0.186691414219734305 ether,
            0.3 ether,
            path,
            address(this)
        );

        // Swap 0.3 TKNA for ~0.186 TKNB
        assertEq(
            tokenA.balanceOf(address(this)),
            20 ether - 1 ether - 0.3 ether
        );
        assertEq(tokenB.balanceOf(address(this)), 20 ether - 2 ether);
        assertEq(
            tokenC.balanceOf(address(this)),
            20 ether - 1 ether + 0.186691414219734305 ether
        );
    }
}
