// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*//////////////////////////////////////////////////////////////
                        UMA INTERFACES
//////////////////////////////////////////////////////////////*/

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

interface OptimisticOracleV3Interface {
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
    ) external returns (bytes32);

    function disputeAssertion(bytes32 assertionId, address disputer) external;
}

interface OptimisticOracleV3CallbackRecipientInterface {
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external;
}

/*//////////////////////////////////////////////////////////////
                    UMA OPTIMISTIC ASSERTION MARKET
//////////////////////////////////////////////////////////////*/

contract UmaOptimisticAssertionMarket
    is OptimisticOracleV3CallbackRecipientInterface
{
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error NotOracle();
    error UnknownAssertion();
    error AlreadyResolved();
    error NotResolved();
    error AlreadySettled();
    error InvalidETH();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event Asserted(bytes32 indexed assertionId, address indexed asserter);
    event Disputed(bytes32 indexed assertionId, address indexed disputer);
    event Resolved(bytes32 indexed assertionId, bool truthful);
    event Settled(bytes32 indexed assertionId, address indexed recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            STORAGE (PACKED)
    //////////////////////////////////////////////////////////////*/
    struct Assertion {
        address asserter;     // winner if TRUE
        address disputer;     // winner if FALSE
        uint96 bond;
        uint96 stake;
        bool resolved;
        bool truthful;
        bool settled;
    }

    mapping(bytes32 => Assertion) public assertions;

    OptimisticOracleV3Interface public immutable oracle;
    IWETH public immutable weth;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _oracle, address _weth) {
        oracle = OptimisticOracleV3Interface(_oracle);
        weth = IWETH(_weth);
    }

    /*//////////////////////////////////////////////////////////////
                        ASSERTION CREATION
    //////////////////////////////////////////////////////////////*/
    function assertTruthETH(
        bytes calldata claim,
        uint64 liveness,
        bytes32 identifier,
        uint256 bondAmount
    ) external payable returns (bytes32 assertionId) {
        if (msg.value < bondAmount || bondAmount == 0) revert InvalidETH();

        uint256 stakeAmount;
        unchecked {
            stakeAmount = msg.value - bondAmount;
        }

        // Wrap ETH -> WETH for UMA bond
        weth.deposit{value: bondAmount}();
        weth.approve(address(oracle), bondAmount);

        assertionId = oracle.assertTruth(
            claim,
            msg.sender,
            address(this),
            address(0),
            liveness,
            IERC20(address(weth)),
            bondAmount,
            identifier,
            bytes32(0)
        );

        assertions[assertionId] = Assertion({
            asserter: msg.sender,
            disputer: address(0),
            bond: uint96(bondAmount),
            stake: uint96(stakeAmount),
            resolved: false,
            truthful: false,
            settled: false
        });

        emit Asserted(assertionId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        DISPUTE HANDLING
    //////////////////////////////////////////////////////////////*/
    function disputeAssertionETH(bytes32 assertionId) external payable {
        Assertion storage a = assertions[assertionId];
        if (a.asserter == address(0)) revert UnknownAssertion();
        if (a.resolved) revert AlreadyResolved();
        if (msg.value != a.bond) revert InvalidETH();

        // Wrap ETH -> WETH for dispute bond
        weth.deposit{value: msg.value}();
        weth.approve(address(oracle), msg.value);

        oracle.disputeAssertion(assertionId, msg.sender);

        a.disputer = msg.sender;

        emit Disputed(assertionId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE CALLBACK
    //////////////////////////////////////////////////////////////*/
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) external override {
        if (msg.sender != address(oracle)) revert NotOracle();

        Assertion storage a = assertions[assertionId];
        if (a.asserter == address(0)) revert UnknownAssertion();
        if (a.resolved) revert AlreadyResolved();

        // CEI: state update first
        a.resolved = true;
        a.truthful = assertedTruthfully;

        emit Resolved(assertionId, assertedTruthfully);
    }

    /*//////////////////////////////////////////////////////////////
                            SETTLEMENT
    //////////////////////////////////////////////////////////////*/
    function settle(bytes32 assertionId) external {
        Assertion storage a = assertions[assertionId];
        if (!a.resolved) revert NotResolved();
        if (a.settled) revert AlreadySettled();

        a.settled = true;

        uint256 payout = a.stake;
        if (payout == 0) return;

        address recipient = a.truthful ? a.asserter : a.disputer;

        (bool ok, ) = recipient.call{value: payout}("");
        require(ok, "ETH_TRANSFER_FAILED");

        emit Settled(assertionId, recipient, payout);
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE ETH
    //////////////////////////////////////////////////////////////*/
    receive() external payable {}
}
