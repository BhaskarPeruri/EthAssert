// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Script.sol";
// import "../src/UmaAssertionMarket.sol";

// contract SettleScript is Script {
//     address constant MARKET =
//         0x33FBD3a20bdbB2E5fD0373c6dF5c17cCf8430A25;

//     // Same assertionId
//     bytes32 constant ASSERTION_ID =
//         0xPASTE_ASSERTION_ID_HERE;

//     function run() external {
//         uint256 pk = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(pk);

//         UmaAssertionMarket market = UmaAssertionMarket(payable(MARKET));
//         market.settle(ASSERTION_ID);

//         vm.stopBroadcast();
//     }
// }
