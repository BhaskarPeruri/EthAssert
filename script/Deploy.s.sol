// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/contracts/ UmaAssertionMarket.sol";

contract DeploySepolia is Script {
    /*//////////////////////////////////////////////////////////////
                    SEPOLIA ADDRESSES (UMA)
    //////////////////////////////////////////////////////////////*/

    // UMA Optimistic Oracle V3 (Sepolia)
    address constant UMA_OO_V3 =
        0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944;

    // WETH on Sepolia
    address constant WETH_SEPOLIA =
        0xdd13E55209Fd76AfE204dBda4007C227904f0a81;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        UmaAssertionMarket market =
            new UmaAssertionMarket(
                UMA_OO_V3,
                WETH_SEPOLIA
            );

        vm.stopBroadcast();

        console2.log(
            "UmaAssertionMarket deployed at:",
            address(market)
        );
    }
}
