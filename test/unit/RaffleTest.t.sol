// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {VRFCoordinatorV2Mock} from "../mocks/VRFCoordinatorV2Mock.sol";
import {CreateSubscription} from "../../script/Interactions.s.sol";

contract RaffleTest is StdCheats, Test {
    /* Errors */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player, uint256 indexed fee);
    event WinnerPicked(address indexed winner);
    event TestEvent(string someString, uint256 indexed someNumber, address indexed someAddress, string someOtherString);

    Raffle public raffle;
    HelperConfig public helperConfig;

    uint64 subscriptionId;
    bytes32 gasLane;
    uint256 automationUpdateInterval;
    uint256 raffleEntranceFee;
    uint32 callbackGasLimit;
    address vrfCoordinatorV2;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig, ) = deployer.run();
        deal(PLAYER, STARTING_USER_BALANCE);

        (
            ,
            gasLane,
            automationUpdateInterval,
            raffleEntranceFee,
            callbackGasLimit,
            vrfCoordinatorV2, // link
            // deployerKey
            ,

        ) = helperConfig.activeNetworkConfig();
    }

    function testRaffleInitializesInOpenState() public view {
        /// @dev Since "RaffleState" is enum (type) we can see it even if it's private and call it like below:
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /////////////////////////
    // enterRaffle         //
    /////////////////////////

    function testRaffleRevertsWHenYouDontPayEnought() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        /// @dev We are checking what exact revert we are getting
        /// @dev Since "Error's" are also states like enum (type) we can call it as below:
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: raffleEntranceFee}();
        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        // Arrange
        vm.prank(PLAYER);

        // Act / Assert
        /// @dev 1st = indexed param(check), 2nd = indexed param(check), 3rd = indexed param(check) (contracts allow only 3 indexed params)
        // 4th = checkData bool(check non-indexed params)
        vm.expectEmit(true, true, false, true, address(raffle));
        emit RaffleEnter(PLAYER, raffleEntranceFee);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        /// @dev "vm.warp" sets `block.timestamp`
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        /// @dev "vm.roll" sets `block.number`
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act / Assert
        /// @dev We are checking what exact revert we are getting
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }

    /////////////////////////
    // checkUpkeep         //
    /////////////////////////
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    /////////////////////////
    // performUpkeep       //
    /////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrueAndEmitsRequestId() public {
        // Arrange
        bytes32 requestId;
        string memory someString;
        bytes32 someNumber;
        address someAddress;
        string memory someOtherString;

        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act / Assert
        vm.expectEmit(false, false, false, false, address(raffle));
        // We do not care about actual requestId (it is 1 btw) we only check if it emits event, so we can confirm "performUpkeep" actually passed
        emit RequestedRaffleWinner(uint256(requestId));
        vm.expectEmit(false, false, false, false, address(raffle));
        emit TestEvent(someString, uint256(someNumber), someAddress, someOtherString);

        // Now we are checking what exact requestId have been emitted
        // below `vm.recordLogs()` is telling VM to start recording all emitted events. We can access them via `vm.getRecordedLogs()`
        vm.recordLogs();
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /// @dev Index of is: `event = entries[x]` while topics[0] = whole emit, so in this case `emit RequestedRaffleWinner(requestId);`, while topics[1] = requestId
        // topics[2] -> this will give you second emitted value etc.
        // WE CAN ONLY READ "INDEXED" PARAMETERS OR STRINGS
        requestId = entries[1].topics[1];

        // Getting Emit from VRFCoordinatorV2
        bytes32 subId = entries[0].topics[2];

        console.log("VRF Emit: ", uint256(subId));
        console.log("Emitted RequestId: ", uint256(requestId));

        assert(uint256(requestId) > 0);

        /// @dev Checking Test Event
        // Mapping unindexed data...
        (string memory s1, string memory s2) = abi.decode(entries[2].data, (string, string));

        someString = abi.decode(entries[2].data, (string));
        someNumber = entries[2].topics[1];
        someAddress = address(uint160(uint256(entries[2].topics[2])));
        someOtherString = s2;

        console.log("String: ", someString, "And", s1);
        console.log("Number: ", uint256(someNumber));
        console.log("Address: ", someAddress, "msg.sender from Raffle.sol will be address(this) here: ", address(this));
        console.log("Other String: ", someOtherString);
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        // Act / Assert
        /// @dev We are checking what exact revert we are getting
        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState));
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleState() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act
        raffle.performUpkeep("");

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        assert(uint(raffleState) == 1); // 0 = open, 1 = calculating
    }

    /////////////////////////
    // fulfillRandomWords //
    ////////////////////////

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    // Skipping tests because of differences between VRFMock and VRF real contracts (Those tests will be included in "staging" folder)
    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    /// @dev Fuzz Testing -> Foundry is generating random inputs and run a looot of times testing if output is the same
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork {
        // Arrange / Act / Assert
        /// @dev This error message comes from VRFCoordinatorV2
        vm.expectRevert("nonexistent request");
        // vm.mockCall could be used here...
        /// @dev Only Chainlink node can call fulfillRandomWords, so we are pretending here to be this Chainlink node
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork {
        address winner;
        address expectedWinner = address(1);

        // Arrange
        uint256 additionalEntrances = 3;
        uint256 startingIndex = 1; // We have starting index be 1 so we can start with address(1) and not address(0)

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrances; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            raffle.enterRaffle{value: raffleEntranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;
        console.log("Starting Balance: ", startingBalance);

        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emits requestId and winner
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; // get the requestId from the logs

        vm.expectEmit(true, false, false, false, address(raffle));
        emit WinnerPicked(expectedWinner);

        vm.recordLogs();
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(uint256(requestId), address(raffle)); // emits requestId and winner
        Vm.Log[] memory secEntries = vm.getRecordedLogs();
        winner = address(uint160(uint256(secEntries[1].topics[1]))); // get recent winner from logs
        console.log("Winner: ", winner);

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = raffleEntranceFee * (additionalEntrances + 1);

        console.log("Recent Winner: ", recentWinner);
        assert(recentWinner == winner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
        assert(raffle.getNumberOfPlayers() == 0);
    }

    /// @dev Getters

    function testGetNumWords() public {
        uint256 numWords = raffle.getNumWords();

        assertEq(numWords, 1);
    }

    function testGetRequestConfirmations() public {
        uint256 requests = raffle.getRequestConfirmations();

        assertEq(requests, 3);
    }

    function testGetInterval() public {
        uint256 interval = raffle.getInterval();

        assertEq(interval, 30);
    }

    function testGetEntranceFee() public {
        uint256 fee = raffle.getEntranceFee();

        assertEq(fee, raffleEntranceFee);
    }

    function testGetNumberOfPlayers() public {
        uint256 players = raffle.getNumberOfPlayers();

        assertEq(players, 0);

        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        players = raffle.getNumberOfPlayers();

        assertEq(players, 1);
    }
}
