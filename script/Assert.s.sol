// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/contracts/ UmaAssertionMarket.sol";

contract AssertScript is Script {
    address constant MARKET =
        0x33FBD3a20bdbB2E5fD0373c6dF5c17cCf8430A25;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        UmaAssertionMarket market = UmaAssertionMarket(payable(MARKET));

        bytes memory claim =
            bytes("ETH price was above $2500 on Feb 1 2026 UTC");

        uint64 liveness = 3600; // 1 hour
        bytes32 identifier = bytes32("ASSERT_TRUTH");
        uint256 bond = 0.01 ether;
        uint256 stake = 0.01 ether;

        bytes32 assertionId = market.assertTruthETH{value: bond + stake}(
            claim,
            liveness,
            identifier,
            bond
        );

        vm.stopBroadcast();

        console2.logBytes32(assertionId);
    }
}
