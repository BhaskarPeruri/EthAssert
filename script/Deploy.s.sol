// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/UmaAssertionMarket.sol";

contract DeployScript is Script {
    function run() external returns (UmaAssertionMarket market) {
        uint256 deployerPk = vm.envUint("OWNER_PRIVATE_KEY");
        vm.startBroadcast(deployerPk);

        address ORACLE =
            0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944;


        address WETH =
            0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;


        address OWNER = vm.addr(deployerPk);

        market = new UmaAssertionMarket(
            ORACLE,
            WETH,
            OWNER
        );

        console2.log("UmaAssertionMarket deployed at:");
        console2.logAddress(address(market));

        vm.stopBroadcast();
    }
}
