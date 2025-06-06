// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract VRFConsumerBaseV2 {
    error OnlyCoordinatorCanFulfill (address have, address want);
    address private immutable vrfCoordinator;

    constructor(address _vrfCoordinator) {
        vrfCoordinator = _vrfCoordinator;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal virtual;

    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        if (msg.sender != vrfCoordinator) {
            revert OnlyCoordinatorCanFulfill(msg.sender, vrfCoordinator);
        }
        fulfillRandomWords(requestId, randomWords);
    }
}

interface IOwnable {
    function owner() external returns (address);

    function transferOwnership(address recipient) external;

    function acceptOwnership() external;
}

contract ConfirmedOwnerWithProposal is IOwnable {
    address private s_owner;
    address private s_pendingOwner;

    event OwnershipTransferRequested(address indexed from, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);

    constructor(address newOwner, address pendingOwner) {
        require(newOwner != address(0), "Cannot set owner to zero");

        s_owner = newOwner;
        if (pendingOwner != address(0)) {
            _transferOwnership(pendingOwner);
        }
    }

    function transferOwnership(address to) public override onlyOwner {
        _transferOwnership(to);
    }

    function acceptOwnership() external override {
        require(msg.sender == s_pendingOwner, "Must be proposed owner");

        address oldOwner = s_owner;
        s_owner = msg.sender;
        s_pendingOwner = address(0);

        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    function owner() public view override returns (address) {
        return s_owner;
    }

    function _transferOwnership(address to) private {
        require(to != msg.sender, "Cannot transfer to self");

        s_pendingOwner = to;

        emit OwnershipTransferRequested(s_owner, to);
    }

    function _validateOwnership() internal view {
        require(msg.sender == s_owner, "Only callable by owner");
    }

    modifier onlyOwner() {
        _validateOwnership();
        _;
    }
}

contract ConfirmedOwner is ConfirmedOwnerWithProposal {
    constructor(address newOwner) ConfirmedOwnerWithProposal(newOwner, address(0)) {}
}

interface VRFCoordinatorV2Interface {
    function getRequestConfig() external view returns (uint16, uint32, bytes32[] memory);

    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId);

    function createSubscription() external returns (uint64 subId);

    function getSubscription(
        uint64 subId
    ) external view returns (uint96 balance, uint64 reqCount, address owner, address[] memory consumers);

    function requestSubscriptionOwnerTransfer(uint64 subId, address newOwner) external;

    function acceptSubscriptionOwnerTransfer(uint64 subId) external;

    function addConsumer(uint64 subId, address consumer) external;

    function removeConsumer(uint64 subId, address consumer) external;

    function cancelSubscription(uint64 subId, address to) external;

    function pendingRequestExists(uint64 subId) external view returns (bool);
}

contract Lottery is VRFConsumerBaseV2, ConfirmedOwner {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event ParticipantAdded(uint256 index, address participant);
    event TicketAssigned(address participant,uint256 ticketNumber);

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }

    mapping(uint256 => RequestStatus) public s_requests;
    VRFCoordinatorV2Interface COORDINATOR;

    mapping(address => uint256) public participantTicket;

    uint64 s_subscriptionId;

    uint256 public lotteryCount = 0;


    address[] public participants;
    uint256[] public tickets;

    uint256[] public requestIds;
    uint256 public lastRequestId;

    bytes32 keyHash =
        0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef;

    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 2;

    constructor(
        uint64 subscriptionId
    )
        VRFConsumerBaseV2(0xa842a38CD758f8dE8537C5CBcB2006DB0250eC7C)
        ConfirmedOwner(msg.sender)
    {
        COORDINATOR = VRFCoordinatorV2Interface(
            0xa842a38CD758f8dE8537C5CBcB2006DB0250eC7C
        );
        s_subscriptionId = subscriptionId;
    }

    function requestRandomWords()
        external
        onlyOwner
        returns (uint256 requestId)
    {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }


    function populateParticipants(address[] memory _participants) external {
        require(_participants.length > 0,"Invalid Input");

        for(uint256 i = 0; i < _participants.length; i++) {
            require(_participants[i] != address(0), "Invalid Address");
            participants.push(_participants[i]);
            tickets.push(lotteryCount);
            lotteryCount++;
            emit ParticipantAdded(i,_participants[i]);
        }
    }


    function generateWinnerUsingRandom(uint256 _requestId, uint256 startPoint) external {
        require(s_requests[_requestId].fulfilled, "Request Not Fulfied");
        uint256 randomNum = s_requests[_requestId].randomWords[0];        
            
        uint256 limit = 0;
        if (startPoint + 500 < participants.length) {
            limit = startPoint + 500;
        } else {
            limit = participants.length;
        }
        for (uint256 j = startPoint; j < limit; j++) {

            uint256 randomTicket = uint160(participants[j]) % randomNum;
            uint256 index = randomTicket%tickets.length;
            uint256 assignedTicket = tickets[index];
            participantTicket[participants[j]] = assignedTicket;

            if (index != tickets.length - 1) {
                tickets[index] = tickets[tickets.length - 1];
            }
            tickets.pop();
            // winnerList.push(Winners(participants[lotteryCount],tickets[ticketIndex]));
            emit TicketAssigned(participants[j],randomTicket);
            
        }
    }
}