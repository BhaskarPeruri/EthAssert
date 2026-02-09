// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

interface UmaAssertionMarket {
    function assertTruthETH(
        bytes calldata claim,
        uint64 liveness,
        bytes32 identifier
    ) external payable returns (bytes32);
}

contract AssertScript is Script {
    // 🔁 Replace if redeployed
    address constant MARKET =
        0xE524748488cC11b9AA44bFbf59e5566582D3B525;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY_USER1");
        vm.startBroadcast(pk);

        /*//////////////////////////////////////////////////////////////
                            ASSERTION DATA
        //////////////////////////////////////////////////////////////*/

        bytes memory claim =
            bytes("ETH price was above $2500 on Feb 1 2026 UTC");

        // 1 hour liveness
        uint64 liveness = 3600;

        // UMA-whitelisted identifier
        bytes32 identifier = "ASSERT_TRUTH";

        /**
         * ETH sent = minBond(WETH) + stake
         *
         * Contract derives bond internally via getMinimumBond(WETH)
         */
        uint256 ethAmount = 0.05 ether;

        bytes32 assertionId =
            UmaAssertionMarket(MARKET).assertTruthETH{value: ethAmount}(
                claim,
                liveness,
                identifier
            );

        console2.log("Assertion created:");
        console2.logBytes32(assertionId);

        vm.stopBroadcast();
    }
}
