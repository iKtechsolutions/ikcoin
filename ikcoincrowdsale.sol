// 11/11/2021 iK Tech Solutions - IKcoin - iKC
//SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./ikcointoken.sol";

interface IStdReference {
    /// A structure returned whenever someone requests for standard reference data.
    struct ReferenceData {
        uint256 rate; // base/quote exchange rate, multiplied by 1e18.
        uint256 lastUpdatedBase; // UNIX epoch of the last time when base price gets updated.
        uint256 lastUpdatedQuote; // UNIX epoch of the last time when quote price gets updated.
    }

    /// Returns the price data for the given base/quote pair. Revert if not available.
    function getReferenceData(string memory _base, string memory _quote)
        external
        view
        returns (ReferenceData memory);
}

contract IKcoinTokensCrowdsale {
    using SafeMath for uint256;
    IStdReference internal ref;

    /**
     * Event for IKcoinTokens purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value bnbs paid for purchase
     * @param IKcoinTokenAmount amount of ik tokens purchased
     */
    event TokenPurchase(
        address indexed purchaser,
        address indexed beneficiary,
        uint256 value,
        uint256 IKcoinTokenAmount
    );

    bool public isEnded = false;

    event Ended(
        uint256 totalBNBRaisedInCrowdsale,
        uint256 unsoldTokensTransferredToOwner
    );
    
      event Transfer(address indexed from, address indexed to, uint256 value);

    uint256 public currentIKcoinTokenUSDPrice; //IKcoinTokens in $USD

    IKCOINToken public ikcoin;

    uint8 public currentCrowdsaleStage;

    // IKcoin Token Distribution
    // =============================
    uint256 public totalIKcoinTokensForSale = 1500000000 * (1e18); // 1.5B IKcoin will be sold during the whole Crowdsale
    // ==============================

    // Amount of bnb raised in Crowdsale
    // ==================
    uint256 public totalBNBRaised;
    // ===================

    // Crowdsale Stages Details
    // ==================
    mapping(uint256 => uint256) public remainingIKcoinInStage;
    mapping(uint256 => uint256) public ikcoinUSDPriceInStages;
    // ===================

    // Events
    event BNBTransferred(string text);

    //Modifier
    address payable public owner;
    address public manager;
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    // Constructor
    // ============
    constructor() public {
        owner = msg.sender;
        manager = msg.sender;
        currentCrowdsaleStage = 1;

        remainingIKcoinInStage[1] = 800000000 * 1e18; // 800M IKcoin will be sold during the Stage 1
        remainingIKcoinInStage[2] = 400000000 * 1e18; // 400M IKcoin will be sold during the Stage 2
        remainingIKcoinInStage[3] = 200000000 * 1e18; // 200M IKcoin will be sold during the Stage 3

        ikcoinUSDPriceInStages[1] = 2000000000000000; //$0.002
        ikcoinUSDPriceInStages[2] = 20000000000000000; //$0.02
        ikcoinUSDPriceInStages[3] = 40000000000000000; //$0.04

        currentIKcoinTokenUSDPrice = ikcoinUSDPriceInStages[1];

        ref = IStdReference(0xDA7a001b254CD22e46d3eAB04d937489c93174C3);
        ikcoin = new IKCOINToken(owner); // IKcoin Token Deployment
    }

    // =============

        // Change Price of each IKC
    function changePrice(uint256 _usd) public onlyOwner {
        currentIKcoinTokenUSDPrice = _usd;
    }

    // Change Crowdsale Stage.
    function switchToNextStage() public onlyOwner {
        currentCrowdsaleStage = currentCrowdsaleStage + 1;
        if ((currentCrowdsaleStage == 4) || (currentCrowdsaleStage == 0)) {
            endCrowdsale();
        }
        currentIKcoinTokenUSDPrice = ikcoinUSDPriceInStages[currentCrowdsaleStage];
    }

    // Change Crowdsale Stage.
    function switchToOtherStage(uint8 _stage) public onlyOwner {
        currentCrowdsaleStage = _stage;
        if ((currentCrowdsaleStage == 4) || (currentCrowdsaleStage == 0)) {
            endCrowdsale();
        }
        currentIKcoinTokenUSDPrice = ikcoinUSDPriceInStages[currentCrowdsaleStage];
    }

    /**
     * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met. Use super to concatenate validations.
     * @param _beneficiary Address performing the ik coin purchase
     */
    function _preValidatePurchase(address _beneficiary) internal pure {
        require(_beneficiary != address(0));
    }

    /**
     * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
     * @param _beneficiary Address performing the IKcoinTokens purchase
     * @param _tokenAmount Number of ikc tokens to be purchased
     */
    function _deliverTokens(address _beneficiary, uint256 _tokenAmount)
        internal
    {
        ikcoin.transfer(_beneficiary, _tokenAmount);
    }

    /**
     * @dev Executed when a purchase has been validated and is ready to be executed. Not necessarily emits/sends tokens.
     * @param _beneficiary Address receiving the tokens
     * @param _tokenAmount Number of ikc tokens to be purchased
     */
    function _processPurchase(address _beneficiary, uint256 _tokenAmount)
        internal
    {
        _deliverTokens(_beneficiary, _tokenAmount);
    }

    /**
     * @dev Override to extend the way in which bnb is converted to tokens.
     * @param _bnbAmount Value in bnb to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _bnbAmount
     */
    function _getTokenAmount(uint256 _bnbAmount)
        internal
        view
        returns (uint256)
    {
        return
            _bnbAmount.mul(getLatestBNBPrice()).div(currentIKcoinTokenUSDPrice);
    }

    // IKcoinTokens Purchase
    // =========================
    receive() external payable {
        if (isEnded) {
            revert(); //Block Incoming BNB Deposits if Crowdsale has ended
        }
        buyIKcoinTokens(msg.sender);
    }

    function buyIKcoinTokens(address _beneficiary) public payable {
        uint256 bnbAmount = msg.value;
        require(bnbAmount > 0, "Please Send some BNB");
        if (isEnded) {
            revert();
        }

        _preValidatePurchase(_beneficiary);
        uint256 IKcoinTokensToBePurchased = _getTokenAmount(bnbAmount);
        if (
            IKcoinTokensToBePurchased >
            remainingIKcoinInStage[currentCrowdsaleStage]
        ) {
            revert(); //Block Incoming BNB Deposits if tokens to be purchased, exceeds remaining tokens for sale in the current stage
        }
        _processPurchase(_beneficiary, IKcoinTokensToBePurchased);
        emit TokenPurchase(
            msg.sender,
            _beneficiary,
            bnbAmount,
            IKcoinTokensToBePurchased
        );

        totalBNBRaised = totalBNBRaised.add(bnbAmount);
        remainingIKcoinInStage[currentCrowdsaleStage] = remainingIKcoinInStage[
            currentCrowdsaleStage
        ].sub(IKcoinTokensToBePurchased);

        if (remainingIKcoinInStage[currentCrowdsaleStage] == 0) {
            switchToNextStage(); // Switch to Next Crowdsale Stage when all tokens allocated for current stage are being sold out
        }
    }

    // Finish: Finalizing the Crowdsale.
    // ====================================================================

    function endCrowdsale() public onlyOwner {
        require(!isEnded, "Crowdsale already finalized");
        uint256 unsoldTokens = ikcoin.balanceOf(address(this));

        if (unsoldTokens > 0) {
            ikcoin.burn(unsoldTokens);
        }
        for (uint8 i = 1; i <= 3; i++) {
            remainingIKcoinInStage[i] = 0;
        }

        currentCrowdsaleStage = 0;
        emit Ended(totalBNBRaised, unsoldTokens);
        isEnded = true;
    }

    // ===============================

     function ikcoinTokenBalance_Owner()
        external
        view
        returns (uint256 balance)
    {
        return ikcoin.balanceOf(address(this));
    }



    // ===============================

    function ikcoinTokenBalance(address tokenHolder)
        external
        view
        returns (uint256 balance)
    {
        return ikcoin.balanceOf(tokenHolder);
    }

    /**
     * Returns the latest BNB-USD price
     */
    function getLatestBNBPrice() public view returns (uint256) {
        IStdReference.ReferenceData memory data = ref.getReferenceData(
            "BNB",
            "USD"
        );
        return data.rate;
    }

    function withdrawFunds(uint256 amount) public onlyOwner {
        require(amount <= address(this).balance, "Insufficient Funds");
        owner.transfer(amount);
        emit BNBTransferred("Funds Withdrawn to Owner Account");
    }

    function transferIKCOwnership_Principal(address _newOwner)
        public
        onlyOwner
    {
        return ikcoin.transferOwnership(_newOwner);
    }

    //Novas funcoes e variaveis

    function getPresaleToken_Principal() external view returns (address) {
        return ikcoin.getOwner();
    }

    function decimals_Principal() external view returns (uint8) {
        return ikcoin.decimals();
    }

    function symbol_Principal() external view returns (string memory) {
        return ikcoin.symbol();
    }

    function name_Principal() external view returns (string memory) {
        return ikcoin.name();
    }

    function totalSupply_Principal() external view returns (uint256) {
        return ikcoin.totalSupply();
    }

    function maxSupply_Principal() external view returns (uint256) {
        return ikcoin.maxSupply();
    }

    //------------------------------------------------------------------//

    function approve_Principal(address spender, uint256 amount)
        public
        onlyOwner
        returns (bool)
    {
        return ikcoin.approve(spender, amount);
    }


    function transfer_Principal(address recipient, uint256 amount)
        public
        onlyOwner
        returns (bool)
    {
        return ikcoin.transfer(recipient, amount);
    }

    function transferFrom_Principal(
        address sender,
        address recipient,
        uint256 amount
    ) public onlyOwner returns (bool) {
        return ikcoin.transferFrom(sender, recipient, amount);
    }

    function increaseAllowance_Principal(address spender, uint256 addedValue)
        public
        onlyOwner
        returns (bool)
    {
        return ikcoin.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance_Principal(
        address spender,
        uint256 subtractedValue
    ) public onlyOwner returns (bool) {
        return ikcoin.decreaseAllowance(spender, subtractedValue);
    }

    function setManager(address _newManager) public onlyOwner {
        require(_newManager != address(0), "Invalid address");
        manager = _newManager;
    }

    function burn_Principal(uint256 amount) public onlyOwner {
        ikcoin.burn(amount);
    }

    function mint_Principal(uint256 amount) public onlyOwner {
        ikcoin.mint(amount);
    }
}
