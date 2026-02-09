// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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

    function getMinimumBond(address currency) external view returns (uint256);

    function syncUmaParams(bytes32 identifier, address currency) external;
}

interface OptimisticOracleV3CallbackRecipientInterface {
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external;
    function assertionDisputedCallback(bytes32 assertionId) external;
}

/*//////////////////////////////////////////////////////////////
                    UMA OPTIMISTIC ASSERTION MARKET
//////////////////////////////////////////////////////////////*/

contract UmaAssertionMarket is
    OptimisticOracleV3CallbackRecipientInterface,
    ReentrancyGuard
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
    event Asserted(bytes32 indexed assertionId, address indexed asserter, uint256 bond);
    event Disputed(bytes32 indexed assertionId, address indexed disputer);
    event Resolved(bytes32 indexed assertionId, bool truthful);
    event Settled(bytes32 indexed assertionId, address indexed recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    struct Assertion {
        address asserter;
        address disputer;
        uint96 bond;     // WETH bond amount
        uint96 stake;    // ETH stake
        bool resolved;
        bool truthful;
        bool settled;
    }

    mapping(bytes32 => Assertion) public assertions;

    OptimisticOracleV3Interface public immutable oracle;
    IWETH public immutable weth;
    address public immutable owner;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _oracle,
        address _weth,
        address _owner
    ) {
        oracle = OptimisticOracleV3Interface(_oracle);
        weth = IWETH(_weth);
        owner = _owner;

        // Sync UMA params so minBond(WETH) is non-zero
        oracle.syncUmaParams("ASSERT_TRUTH", _weth);
    }

    /*//////////////////////////////////////////////////////////////
                        ASSERTION CREATION
    //////////////////////////////////////////////////////////////*/
    function assertTruthETH(
        bytes calldata claim,
        uint64 liveness,
        bytes32 identifier
    )
        external
        payable
        nonReentrant
        returns (bytes32 assertionId)
    {
        uint256 minBond = oracle.getMinimumBond(address(weth));
        if (minBond == 0 || msg.value <= minBond) revert InvalidETH();

        uint256 bond = minBond;
        uint256 stake = msg.value - bond;

        // Wrap ETH → WETH for UMA bond
        weth.deposit{value: bond}();
        weth.approve(address(oracle), bond);

        assertionId = oracle.assertTruth(
            claim,
            msg.sender,
            address(this), // callback recipient
            address(0),
            liveness,
            IERC20(address(weth)),
            bond,
            identifier,
            bytes32(0)
        );

        assertions[assertionId] = Assertion({
            asserter: msg.sender,
            disputer: address(0),
            bond: uint96(bond),
            stake: uint96(stake),
            resolved: false,
            truthful: false,
            settled: false
        });

        emit Asserted(assertionId, msg.sender, bond);
    }

    /*//////////////////////////////////////////////////////////////
                        DISPUTE HANDLING
    //////////////////////////////////////////////////////////////*/
    function disputeAssertionETH(bytes32 assertionId)
        external
        payable
        nonReentrant
    {
        Assertion storage a = assertions[assertionId];
        if (a.asserter == address(0)) revert UnknownAssertion();
        if (a.resolved) revert AlreadyResolved();
        if (msg.value != a.bond) revert InvalidETH();

        // Wrap ETH → WETH for dispute bond
        weth.deposit{value: msg.value}();
        weth.approve(address(oracle), msg.value);

        oracle.disputeAssertion(assertionId, msg.sender);
        a.disputer = msg.sender;

        emit Disputed(assertionId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE CALLBACKS
    //////////////////////////////////////////////////////////////*/
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) external override {
        if (msg.sender != address(oracle)) revert NotOracle();

        Assertion storage a = assertions[assertionId];
        if (a.asserter == address(0)) revert UnknownAssertion();
        if (a.resolved) revert AlreadyResolved();

        a.resolved = true;
        a.truthful = assertedTruthfully;

        emit Resolved(assertionId, assertedTruthfully);
    }

    // REQUIRED BY UMA — must NOT revert
    function assertionDisputedCallback(bytes32 assertionId) external override {
        if (msg.sender != address(oracle)) revert NotOracle();
        // no-op
    }

    /*//////////////////////////////////////////////////////////////
                            SETTLEMENT
    //////////////////////////////////////////////////////////////*/
    function settle(bytes32 assertionId)
        external
        nonReentrant
    {
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
                        EMERGENCY WITHDRAW
    //////////////////////////////////////////////////////////////*/
    function withdrawETH(uint256 amount)
        external
        nonReentrant
    {
        require(msg.sender == owner, "NOT_OWNER");
        require(address(this).balance >= amount, "INSUFFICIENT_BALANCE");

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "ETH_TRANSFER_FAILED");
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getAssertion(bytes32 assertionId) external view returns (Assertion memory) {
        return assertions[assertionId];
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE ETH
    //////////////////////////////////////////////////////////////*/
    receive() external payable {}
}
