// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

import {ZuniswapV2Pair} from "./ZuniswapV2Pair.sol";
import {IZuniswapV2Pair} from "./interfaces/IZuniswapV2Pair.sol";
import {console} from "forge-std/Test.sol";

contract ZuniswapV2Factory {
    error IdenticalAddress();
    error PairExists();
    error ZeroAddress();

    //币对合约创建事件
    event pairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );
    //token[token]pairContract
    mapping(address => mapping(address => address)) public pairs;
    //所有币对合约地址
    address[] public allPairs;

    //创建币对合约,传入两个token地址
    function createPair(
        address tokenA,
        address tokenB
    ) public returns (address pair) {
        if (tokenA == tokenB) {
            revert IdenticalAddress();
        }
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        //地址不能为零地址
        if (token0 == address(0) || token1 == address(0)) {
            revert ZeroAddress();
        }
        //不能重复创建合约
        if (pairs[token0][token1] != address(0)) {
            revert PairExists();
        }
        //使用assembly的create2
        //获取币对合约的字节码
        bytes memory bytecode = type(ZuniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes memory constructorParms = abi.encodePacked(token0, token1);
        bytes memory fullBytecode = abi.encodePacked(
            bytecode,
            constructorParms
        );
        //使用create2方法创建合约地址
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
            // pair := create2(0, add(fullBytecode, 32), mload(fullBytecode), salt)
        }
        console.log(tokenA, tokenB, pair);
        ////直接使用new Contract{salt:salt}()
        // bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // pair = address(new ZuniswapV2Pair{salt: salt}());

        IZuniswapV2Pair(pair).initialize(token0, token1);
        pairs[token0][token1] = pair;
        pairs[token1][token0] = pair;
        allPairs.push(pair);

        emit pairCreated(token0, token1, pair, allPairs.length);
    }
}
