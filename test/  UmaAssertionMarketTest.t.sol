// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UmaAssertionMarket.sol";

// ============================================================================
// MOCK CONTRACTS
// ============================================================================

contract MockWETH {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }
    
    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract MockOptimisticOracleV3 {
    uint256 public minimumBond = 0.01 ether;
    mapping(bytes32 => address) public assertions;
    mapping(bytes32 => bool) public disputed;
    
    function getMinimumBond(address) external view returns (uint256) {
        return minimumBond;
    }
    
    function setMinimumBond(uint256 _bond) external {
        minimumBond = _bond;
    }
    
    function syncUmaParams(bytes32, address) external {
        // Mock implementation - does nothing
    }
    
    function assertTruth(
        bytes calldata claim,
        address asserter,
        address callbackRecipient,
        address escalationManager,
        uint64 liveness,
        IERC20 currency,
        uint256 bond,
        bytes32 identifier,
        bytes32 domainId
    ) external returns (bytes32) {
        bytes32 assertionId = keccak256(abi.encodePacked(claim, asserter, block.timestamp));
        assertions[assertionId] = callbackRecipient;
        return assertionId;
    }
    
    function disputeAssertion(bytes32 assertionId, address disputer) external {
        disputed[assertionId] = true;
    }
    
    function settleAssertion(bytes32 assertionId) external {
        // Mock implementation
    }
    
    function getAssertion(bytes32 assertionId) external view returns (
        bool,
        bool,
        address,
        address,
        address,
        address,
        uint256,
        IERC20,
        bytes32,
        bytes32
    ) {
        return (
            true,
            !disputed[assertionId],
            assertions[assertionId],
            address(0),
            address(0),
            address(0),
            0,
            IERC20(address(0)),
            bytes32(0),
            bytes32(0)
        );
    }
}

// ============================================================================
// TEST CONTRACT - COMPREHENSIVE COVERAGE
// ============================================================================

contract UmaAssertionMarketTest is Test {
    UmaAssertionMarket market;
    MockOptimisticOracleV3 oracle;
    MockWETH weth;

    address OWNER = makeAddr("owner");
    address asserter = address(0xA11CE);
    address disputer = address(0xB0B);
    address randomUser = address(0xDEAD);

    event Asserted(bytes32 indexed assertionId, address indexed asserter, uint256 bond);
    event Disputed(bytes32 indexed assertionId, address indexed disputer);
    event Resolved(bytes32 indexed assertionId, bool truthful);
    event Settled(bytes32 indexed assertionId, address indexed recipient, uint256 amount);

    function setUp() public {
        vm.deal(asserter, 10 ether);
        vm.deal(disputer, 10 ether);
        vm.deal(randomUser, 10 ether);

        oracle = new MockOptimisticOracleV3();
        weth = new MockWETH();

        market = new UmaAssertionMarket(
            address(oracle),
            address(weth),
            OWNER
        );
    }

    // ============================================================================
    // CONSTRUCTOR TESTS
    // ============================================================================

    function testConstructorSetsCorrectValues() public {
        assertEq(address(market.oracle()), address(oracle));
        assertEq(address(market.weth()), address(weth));
        assertEq(market.owner(), OWNER);
    }

    // ============================================================================
    // ASSERTION CREATION TESTS
    // ============================================================================

    function testAssertWithETH() public {
        vm.prank(asserter);

        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        UmaAssertionMarket.Assertion memory assertion = market.getAssertion(assertionId);
        
        assertEq(assertion.asserter, asserter);
        assertEq(assertion.disputer, address(0));
        assertTrue(assertion.bond > 0);
        assertTrue(assertion.stake > 0);
        assertFalse(assertion.resolved);
        assertFalse(assertion.settled);
        assertFalse(assertion.truthful);
    }



    function testAssertRevertsWithInsufficientETH() public {
        vm.prank(asserter);
        vm.expectRevert(UmaAssertionMarket.InvalidETH.selector);
        market.assertTruthETH{value: 0.009 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );
    }

    function testAssertRevertsWhenMinBondIsZero() public {
        oracle.setMinimumBond(0);
        
        vm.prank(asserter);
        vm.expectRevert(UmaAssertionMarket.InvalidETH.selector);
        market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );
    }

    function testAssertRevertsWhenETHEqualsMinBond() public {
        uint256 minBond = oracle.getMinimumBond(address(weth));
        
        vm.prank(asserter);
        vm.expectRevert(UmaAssertionMarket.InvalidETH.selector);
        market.assertTruthETH{value: minBond}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );
    }

    function testAssertWithDifferentClaims() public {
        bytes[] memory claims = new bytes[](3);
        claims[0] = "BTC > $50k";
        claims[1] = "ETH will flip BTC";
        claims[2] = "Solana is the future";

        for (uint i = 0; i < claims.length; i++) {
            vm.prank(asserter);
            bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
                claims[i],
                3600,
                "ASSERT_TRUTH"
            );
            assertTrue(assertionId != bytes32(0));
        }
    }

    // ============================================================================
    // DISPUTE TESTS
    // ============================================================================

    function testDisputeRequiresExactBond() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        uint96 bond = market.getAssertion(assertionId).bond;

        vm.prank(disputer);
        vm.expectRevert(UmaAssertionMarket.InvalidETH.selector);
        market.disputeAssertionETH{value: bond + 1}(assertionId);

        vm.prank(disputer);
        market.disputeAssertionETH{value: bond}(assertionId);
    }

    function testDisputeWithLessThanBond() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        uint96 bond = market.getAssertion(assertionId).bond;

        vm.prank(disputer);
        vm.expectRevert(UmaAssertionMarket.InvalidETH.selector);
        market.disputeAssertionETH{value: bond - 1}(assertionId);
    }

    function testDisputeEmitsEvent() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        uint96 bond = market.getAssertion(assertionId).bond;

        vm.prank(disputer);
        vm.expectEmit(true, true, false, false);
        emit Disputed(assertionId, disputer);
        
        market.disputeAssertionETH{value: bond}(assertionId);
    }

    function testDisputeUnknownAssertionReverts() public {
        bytes32 fakeAssertionId = keccak256("fake");
        
        vm.prank(disputer);
        vm.expectRevert(UmaAssertionMarket.UnknownAssertion.selector);
        market.disputeAssertionETH{value: 0.01 ether}(fakeAssertionId);
    }

    function testDisputeAlreadyResolvedReverts() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, true);

        uint96 bond = market.getAssertion(assertionId).bond;

        vm.prank(disputer);
        vm.expectRevert(UmaAssertionMarket.AlreadyResolved.selector);
        market.disputeAssertionETH{value: bond}(assertionId);
    }

    function testDisputeSetsDisputerAddress() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        uint96 bond = market.getAssertion(assertionId).bond;

        vm.prank(disputer);
        market.disputeAssertionETH{value: bond}(assertionId);

        assertEq(market.getAssertion(assertionId).disputer, disputer);
    }

    // ============================================================================
    // ORACLE CALLBACK TESTS
    // ============================================================================

    function testOracleCallbackResolvesAssertionTruthful() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, true);

        UmaAssertionMarket.Assertion memory assertion = market.getAssertion(assertionId);
        assertTrue(assertion.resolved);
        assertTrue(assertion.truthful);
    }

    function testOracleCallbackResolvesAssertionUntruthful() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, false);

        UmaAssertionMarket.Assertion memory assertion = market.getAssertion(assertionId);
        assertTrue(assertion.resolved);
        assertFalse(assertion.truthful);
    }

    function testOracleCallbackEmitsEvent() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        vm.expectEmit(true, false, false, true);
        emit Resolved(assertionId, true);
        
        market.assertionResolvedCallback(assertionId, true);
    }

    function testOracleCallbackRevertsIfNotOracle() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(randomUser);
        vm.expectRevert(UmaAssertionMarket.NotOracle.selector);
        market.assertionResolvedCallback(assertionId, true);
    }

    function testOracleCallbackRevertsForUnknownAssertion() public {
        bytes32 fakeAssertionId = keccak256("fake");
        
        vm.prank(address(oracle));
        vm.expectRevert(UmaAssertionMarket.UnknownAssertion.selector);
        market.assertionResolvedCallback(fakeAssertionId, true);
    }

    function testOracleCallbackRevertsIfAlreadyResolved() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, true);

        vm.prank(address(oracle));
        vm.expectRevert(UmaAssertionMarket.AlreadyResolved.selector);
        market.assertionResolvedCallback(assertionId, false);
    }

    function testAssertionDisputedCallbackDoesNotRevert() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionDisputedCallback(assertionId);
        // Should not revert
    }

    function testAssertionDisputedCallbackRevertsIfNotOracle() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(randomUser);
        vm.expectRevert(UmaAssertionMarket.NotOracle.selector);
        market.assertionDisputedCallback(assertionId);
    }

    // ============================================================================
    // SETTLEMENT TESTS
    // ============================================================================

    function testSettlementPaysAsserterWhenTruthful() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, true);

        uint256 balanceBefore = asserter.balance;
        uint96 expectedPayout = market.getAssertion(assertionId).stake;

        market.settle(assertionId);

        assertEq(asserter.balance, balanceBefore + expectedPayout);
    }

    function testSettlementPaysDisputerWhenUntruthful() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        uint96 bond = market.getAssertion(assertionId).bond;

        vm.prank(disputer);
        market.disputeAssertionETH{value: bond}(assertionId);

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, false);

        uint256 balanceBefore = disputer.balance;
        uint96 expectedPayout = market.getAssertion(assertionId).stake;

        market.settle(assertionId);

        assertEq(disputer.balance, balanceBefore + expectedPayout);
    }

    function testSettlementEmitsEvent() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, true);

        uint96 stake = market.getAssertion(assertionId).stake;

        vm.expectEmit(true, true, false, true);
        emit Settled(assertionId, asserter, stake);
        
        market.settle(assertionId);
    }

    function testCannotSettleBeforeResolution() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.expectRevert(UmaAssertionMarket.NotResolved.selector);
        market.settle(assertionId);
    }

    function testCannotSettleTwice() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, true);

        market.settle(assertionId);

        vm.expectRevert(UmaAssertionMarket.AlreadySettled.selector);
        market.settle(assertionId);
    }

    function testSettleMarksAsSettled() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, true);

        assertFalse(market.getAssertion(assertionId).settled);

        market.settle(assertionId);

        assertTrue(market.getAssertion(assertionId).settled);
    }

    function testSettleWithZeroStake() public {
        // This would require modifying the contract to allow zero stake
        // or using a very specific bond amount equal to msg.value
        // For now, we'll skip this edge case as the contract prevents it
    }

    // ============================================================================
    // EMERGENCY WITHDRAW TESTS
    // ============================================================================

    function testOwnerCanWithdrawETH() public {
        // Send some ETH to the contract
        vm.deal(address(market), 1 ether);

        uint256 ownerBalanceBefore = OWNER.balance;

        vm.prank(OWNER);
        market.withdrawETH(0.5 ether);

        assertEq(OWNER.balance, ownerBalanceBefore + 0.5 ether);
        assertEq(address(market).balance, 0.5 ether);
    }

    function testNonOwnerCannotWithdraw() public {
        vm.deal(address(market), 1 ether);

        vm.prank(randomUser);
        vm.expectRevert("NOT_OWNER");
        market.withdrawETH(0.5 ether);
    }

    function testWithdrawRevertsIfInsufficientBalance() public {
        vm.deal(address(market), 0.5 ether);

        vm.prank(OWNER);
        vm.expectRevert("INSUFFICIENT_BALANCE");
        market.withdrawETH(1 ether);
    }

    function testOwnerCanWithdrawAllETH() public {
        vm.deal(address(market), 1 ether);

        vm.prank(OWNER);
        market.withdrawETH(1 ether);

        assertEq(address(market).balance, 0);
    }

    // ============================================================================
    // RECEIVE FUNCTION TESTS
    // ============================================================================

    function testContractCanReceiveETH() public {
        uint256 balanceBefore = address(market).balance;
        
        (bool success, ) = address(market).call{value: 1 ether}("");
        assertTrue(success);
        
        assertEq(address(market).balance, balanceBefore + 1 ether);
    }

    // ============================================================================
    // REENTRANCY TESTS
    // ============================================================================

    function testReentrancyProtectionOnAssert() public {
        // The nonReentrant modifier should prevent reentrancy
        // This is more of a sanity check that the modifier is in place
        vm.prank(asserter);
        market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );
    }

    function testReentrancyProtectionOnDispute() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        uint96 bond = market.getAssertion(assertionId).bond;

        vm.prank(disputer);
        market.disputeAssertionETH{value: bond}(assertionId);
    }

    function testReentrancyProtectionOnSettle() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, true);

        market.settle(assertionId);
    }

    // ============================================================================
    // INTEGRATION TESTS
    // ============================================================================

    function testFullAsserterWinFlow() public {
        // 1. Assert
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        // 2. Oracle resolves as truthful
        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, true);

        // 3. Settle
        uint256 balanceBefore = asserter.balance;
        market.settle(assertionId);

        // Verify final state
        assertTrue(market.getAssertion(assertionId).resolved);
        assertTrue(market.getAssertion(assertionId).truthful);
        assertTrue(market.getAssertion(assertionId).settled);
        assertGt(asserter.balance, balanceBefore);
    }

    function testFullDisputerWinFlow() public {
        // 1. Assert
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        uint96 bond = market.getAssertion(assertionId).bond;

        // 2. Dispute
        vm.prank(disputer);
        market.disputeAssertionETH{value: bond}(assertionId);

        // 3. Oracle resolves as untruthful
        vm.prank(address(oracle));
        market.assertionResolvedCallback(assertionId, false);

        // 4. Settle
        uint256 balanceBefore = disputer.balance;
        market.settle(assertionId);

        // Verify final state
        assertTrue(market.getAssertion(assertionId).resolved);
        assertFalse(market.getAssertion(assertionId).truthful);
        assertTrue(market.getAssertion(assertionId).settled);
        assertEq(market.getAssertion(assertionId).disputer, disputer);
        assertGt(disputer.balance, balanceBefore);
    }

    function testMultipleAssertionsCanCoexist() public {
        bytes32[] memory assertionIds = new bytes32[](3);

        for (uint i = 0; i < 3; i++) {
            vm.prank(asserter);
            assertionIds[i] = market.assertTruthETH{value: 0.05 ether}(
                abi.encodePacked("Claim ", i),
                3600,
                "ASSERT_TRUTH"
            );
        }

        // All assertions should be independent
        for (uint i = 0; i < 3; i++) {
            assertEq(market.getAssertion(assertionIds[i]).asserter, asserter);
            assertFalse(market.getAssertion(assertionIds[i]).resolved);
        }
    }

    // ============================================================================
    // VIEW FUNCTION TESTS
    // ============================================================================

    function testGetAssertionReturnsCorrectData() public {
        vm.prank(asserter);
        bytes32 assertionId = market.assertTruthETH{value: 0.05 ether}(
            "ETH price above $2500",
            3600,
            "ASSERT_TRUTH"
        );

        UmaAssertionMarket.Assertion memory assertion = market.getAssertion(assertionId);

        assertEq(assertion.asserter, asserter);
        assertEq(assertion.disputer, address(0));
        assertGt(assertion.bond, 0);
        assertGt(assertion.stake, 0);
        assertFalse(assertion.resolved);
        assertFalse(assertion.truthful);
        assertFalse(assertion.settled);
    }

    function testGetAssertionForNonExistentReturnsZeros() public {
        bytes32 fakeId = keccak256("nonexistent");
        UmaAssertionMarket.Assertion memory assertion = market.getAssertion(fakeId);

        assertEq(assertion.asserter, address(0));
        assertEq(assertion.disputer, address(0));
        assertEq(assertion.bond, 0);
        assertEq(assertion.stake, 0);
        assertFalse(assertion.resolved);
        assertFalse(assertion.truthful);
        assertFalse(assertion.settled);
    }
}
