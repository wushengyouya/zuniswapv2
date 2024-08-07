// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.22;

interface IZuniswapV2Pair {
    //初始化token
    function initialize(address, address) external;

    //获取token总量
    function getReserves() external returns (uint112, uint112, uint32);

    //铸造流动性代币
    function mint(address) external returns (uint256);

    //销毁流动性代币
    function burn(address) external returns (uint256, uint256);

    //转账
    function transferFrom(address, address, uint256) external returns (bool);

    //交换token
    function swap(uint256, uint256, address, bytes calldata) external;
}
