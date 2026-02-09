// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

interface UmaAssertionMarket {
    function assertions(bytes32 id)
        external
        view
        returns (
            address asserter,
            address disputer,
            uint96 bond,
            uint96 stake,
            bool resolved,
            bool truthful,
            bool settled
        );

    function disputeAssertionETH(bytes32 assertionId) external payable;
}

contract DisputeScript is Script {
    // Your deployed UmaAssertionMarket
    address constant MARKET =
        0xE524748488cC11b9AA44bFbf59e5566582D3B525;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY_USER2");
        vm.startBroadcast(pk);


        bytes32 assertionId =
            0xF827D6D55657CF25B55091742632FFAE3B3D629895B7F0692A9F2F00B2723D03;

        (
            address asserter,
            address disputer,
            uint96 bond,
            ,
            bool resolved,
            ,
            bool settled
        ) = UmaAssertionMarket(MARKET).assertions(assertionId);

        require(asserter != address(0), "Assertion does not exist");
        require(disputer == address(0), "Already disputed");
        require(!resolved, "Already resolved");
        require(!settled, "Already settled");
        require(bond > 0, "Invalid bond");

        UmaAssertionMarket(MARKET)
            .disputeAssertionETH{value: uint256(bond)}(assertionId);

        console2.log("Assertion disputed successfully");
        console2.logBytes32(assertionId);
        console2.log("Bond sent (wei):", uint256(bond));

        vm.stopBroadcast();
    }
}
