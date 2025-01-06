// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import {IZuniswapV2Factory} from "./interfaces/IZuniswapV2Factory.sol";
import {IZuniswapV2Pair} from "./interfaces/IZuniswapV2Pair.sol";
import {ZuniswapV2Pair} from "./ZuniswapV2Pair.sol";

library ZuniswapV2Library {
    error InsufficientAmount();
    error InsufficientLiquidity();
    error InvalidPath();

    //获取合约存储的token金额
    function getReserves(
        address factoryAddress,
        address tokenA,
        address tokenB
    ) public returns (uint256 reserveA, uint256 reserveB) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IZuniswapV2Pair(
            pairFor(factoryAddress, token0, token1)
        ).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // 通过计算，保证按照原比例添加流动性，使价格不发生变化
    function queto(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        return (amountIn * reserveOut) / reserveIn;
    }

    //对token地址进行排序
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    //传入factoryAddress,tokenA,tokenB,计算出币对的合约地址
    function pairFor(
        address factoryAddress,
        address tokenA,
        address tokenB
    ) internal pure returns (address pairAddress) {
        //对token地址进行从小到大排序
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pairAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factoryAddress,
                            keccak256(abi.encodePacked(token0, token1)),
                            keccak256(type(ZuniswapV2Pair).creationCode)
                        )
                    )
                )
            )
        );
    }

    /**
     * x * y = k = L ** 2
     * p = y / x
     * 假设确定 In 为 x, Out 为 y
     * swap 公式：△y = △x * y / x + △x
     * 确定输入In token，得出Out Token数,扣除0.3%手续费
     * @param amountIn   要转换的金额
     * @param reserveIn  In存储的总金额
     * @param reserveOut Out存储的总金额
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256) {
        if (amountIn == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 amountInwithFee = amountIn * 997;
        uint256 numerator = amountInwithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInwithFee;

        return numerator / denominator;
    }

    /**
     * 确定out Token,得出in Token,扣除0.3%手续费
     * swap公式：△x = x * △y / y - △y
     * @param amountOut 确定Out的金额数
     * @param reserveIn In总金额数
     * @param reserveOut Out的总金额
     */
    function getAmountIn(
        uint256 amountOut,
        uint reserveIn,
        uint reserveOut
    ) public pure returns (uint256) {
        if (amountOut == 0) revert InsufficientAmount();
        if (reserveIn == 0) revert InsufficientLiquidity();

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;

        return (numerator / denominator) + 1;
    }

    //Token A => Token C  A-B-C
    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory path
    ) public returns (uint256[] memory) {
        if (path.length < 2) revert InvalidPath();
        uint256[] memory amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserve0, uint reserve1) = getReserves(
                factory,
                path[i],
                path[i + 1]
            );
            amounts[i + 1] = getAmountOut(amounts[i], reserve0, reserve1);
        }
        return amounts;
    }

    //A-B-C 三个token
    // C -> B -> A
    //C_outToken => A_inToken
    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path
    ) public returns (uint256[] memory) {
        if (path.length < 2) revert InvalidPath();
        uint256[] memory amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserve0, uint256 reserve1) = getReserves(
                factory,
                path[i - 1],
                path[i]
            );
            amounts[i - 1] = getAmountIn(amounts[i], reserve0, reserve1);
        }
        return amounts;
    }
}
