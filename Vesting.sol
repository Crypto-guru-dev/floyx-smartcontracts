// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
} 

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface TIERC20 {
    // Function to get the total supply of tokens

    function transferFrom(address from, address to, uint256 amount) external;

}

contract Vesting is Ownable {

    struct Project{ 
        string name;
        address signer;
        address token;
        uint256 IDOCount;
        uint256 participantsCount;
        uint256 participantsLimit;
    }

    struct ProjectInvestment{ 
        uint256 id;
        uint256 amount;
        uint256 idoNumber;
        uint8 _paymentOption;
    }

    mapping (uint256=>Project) public projects;
    mapping (address=>mapping(uint256 => bool)) public isInvested;

    mapping (bytes32=>bool) public isRedeemed;
    mapping (bytes32=>bool) public idoClaimed;

    uint256 public idCounter = 0;
    
    address public multiSig;
    address public admin;
    // address[] public paymentOptions = [0xdAC17F958D2ee523a2206206994597C13D831ec7,0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,0xE8799100F8c1C1eD81b62Ba48e9090D5d4f51DC4];
    address[] public paymentOptions = [0x42C0CA9C67a1715E77C6e3280e3B138031B5C2da,0x42C0CA9C67a1715E77C6e3280e3B138031B5C2da,0x42C0CA9C67a1715E77C6e3280e3B138031B5C2da];

    event Validate(address addr, bytes32 message);
    event TGEDeposited(uint256 id,uint256 amount,address depositer,address token);
    event ProjectRegistered(uint256 id,string name, address owner,uint256 totalParticipants);
    event IDOInvested(address investor,uint256 id,uint256 amount,uint256 idoNumber,uint256 _paymentOption);
    event IDOClaimed(address claimer,uint256 id,uint256 amount,uint256 vestingNumber,uint256 idoNumber);


    constructor(address _multiSig, address _admin) {
        multiSig = _multiSig;
        admin = _admin;
    }

    function registerProject(string memory name, address owner,uint256 totalParticipants) external onlyOwner{
        Project memory pr = Project(name,owner,address(0),0,0,totalParticipants);
        projects[idCounter] = pr;
        idCounter++;
        emit ProjectRegistered(idCounter-1,name,owner,totalParticipants);
    }

    function TGE(uint256 _id,uint256 initialSHO, address token, bytes memory signature) external {
        require(projects[_id].signer!=address(0));
        require(token!=address(0),"Invalid Token Address");
        require(initialSHO>0,"Invalid SHO");

        address sender = msg.sender;
        // address signer = projects[_id].signer;
        bytes32 message =  keccak256(abi.encodePacked(_id, sender, initialSHO, token, uint256(0)));
        // console.logBytes32(message);
        (uint8 v, bytes32 r, bytes32 s) = extractRSV(signature);
        _validate(v, r, s, message);
        // isRedeemed[message] = true;
        require(IERC20(token).transferFrom(sender,address(this),initialSHO),"Transfer_Falied");
        projects[_id].token = token;
        projects[_id].IDOCount = 1;

        emit TGEDeposited(_id,initialSHO,token,sender);
    }

    function purchaseIDO(ProjectInvestment memory pi,bytes memory signature) external {
        // require(projects[id].token!=address(0),"No IDO to claim");
        require(projects[pi.id].signer!=address(0));
        require(projects[pi.id].IDOCount > 0, 'Unregistered project');
        require(projects[pi.id].participantsCount<projects[pi.id].participantsLimit,"Participation Limit Reached");

        address sender = msg.sender;
        // address signer = projects[pi.id].signer;
        bytes32 message =  keccak256(abi.encodePacked(pi.id,sender,pi.amount,pi.idoNumber));
        require(!isRedeemed[message],"Signautre Already redeemed");

        (uint8 v, bytes32 r, bytes32 s) = extractRSV(signature);
        _validate(v, r, s, message);

        isRedeemed[message] = true;
        projects[pi.id].participantsCount += 1;
        isInvested[sender][pi.id] = true;

        if(pi._paymentOption==0){
            TIERC20(paymentOptions[pi._paymentOption]).transferFrom(sender,multiSig,pi.amount);
        } else {
            IERC20(paymentOptions[pi._paymentOption]).transferFrom(sender,multiSig,pi.amount);
        }
        emit IDOInvested(sender,pi.id,pi.amount,pi.idoNumber,pi._paymentOption);
    }

    function claimIDO(uint256 id,uint256 amount,uint256 vestingNumber,uint256 idoNumber,bytes memory signature) external {
        require(projects[id].token!=address(0),"No IDO to claim");
        require(projects[id].signer!=address(0));

        address sender = msg.sender;
        // address signer = projects[id].signer;
        address idoToken = projects[id].token;
        bytes32 message =  keccak256(abi.encodePacked(id,sender,amount,vestingNumber,idoNumber));
        require(!idoClaimed[message],"Invalid Status For Claim");

        (uint8 v, bytes32 r, bytes32 s) = extractRSV(signature);
        _validate(v, r, s, message);

        idoClaimed[message] = true;

        IERC20(idoToken).transfer(sender,amount);

        emit IDOClaimed(sender, id, amount,idoNumber, vestingNumber);
    }

    function _validate(
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes32 encodeData
    ) internal view {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, encodeData));
        address recoveredAddress = ecrecover(prefixedHash, v, r, s);

        require(recoveredAddress == admin, "Invalid address");
    }

    function extractRSV(bytes memory signature) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(signature.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
    }

    function updatePaymentOption(address[3] memory _paymentoption) external onlyOwner {
        require(_paymentoption.length==3,"Invalid Array");
        paymentOptions = _paymentoption;
    }

    receive() external payable {}
}