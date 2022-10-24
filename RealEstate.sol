// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

contract realEstate {
	uint8 private decimals;                             // Decimals of our Shares. Has to be 0.
	uint256 constant private MAX_UINT256 = 2**256 - 1;  // Very large number.
	uint256 public totalSupply;                         // By default 100 for 100% ownership. Can be changed.
	uint256 public accumulated;                         // Globally accumulated funds not distributed to stakeholder yet excluding gov.
	uint256 public occupiedUntill;                      // Blocknumber untill the Property is occupied.
	
	string public name;                                 // The name of our house (token). Can be determined in Constructor _propertyID
	string public symbol;                               // The Symbol of our house (token). Can be determined in Constructor _propertySymbol

	address public gov = msg.sender;    	            // Government will deploy contract.
	address public mainPropertyOwner;                   // mainPropertyOwner can change tenant.Can become mainPropertyOwner by claimOwnership if owning > 51% of token.
	
	address[] public stakeholders;                      // Array of stakeholders. Government can addStakeholder or removeStakeholder. Recipient of token needs to be isStakeholder = true to be able to receive token. mainPropertyOwner & Government are stakeholder by default.

	mapping (address => uint256) public revenues;       // Distributed revenue account ballance for each stakeholder including gov.
	mapping (address => uint256) public shares;         // Addresses mapped to token ballances.
	mapping (address => mapping (address => uint256)) private allowed;   // All addresses allow unlimited token withdrawals by the government.
	mapping (address => uint256) public sharesOffered;  //Number of Shares a Stakeholder wants to offer to other stakeholders
    mapping (address => uint256) public shareSellPrice; // Price per Share a Stakeholder wants to have when offering to other Stakeholders


	event ShareTransfer(address indexed from, address indexed to, uint256 shares);
	event Seizure(address indexed seizedfrom, address indexed to, uint256 shares);
	event MainPropertyOwner(address NewMainPropertyOwner);
	event NewStakeHolder(address StakeholderAdded);
	event StakeHolderBanned (address banned);
	event RevenuesDistributed (address shareholder, uint256 gained, uint256 total);
	event Withdrawal (address shareholder, uint256 withdrawn);
	event SharesOffered(address Seller, uint256 AmmountShares, uint256 PricePerShare);
	event SharesSold(address Seller, address Buyer, uint256 SharesSold,uint256 PricePerShare);


	constructor (string memory _propertyID, string memory _propertySymbol, address _mainPropertyOwner) {
		shares[_mainPropertyOwner] = 100;                   //one main Shareholder to be declared by government to get all initial shares.
		totalSupply = 100;                                  //supply fixed to 100 for now, Can also work with 10, 1000, 10 000...
		name = _propertyID;
		decimals = 0;
		symbol = _propertySymbol;
		mainPropertyOwner = _mainPropertyOwner;
		stakeholders.push(gov);                             //gov & mainPropertyOwner pushed to stakeholdersarray upon construction to allow payout and transfers
		stakeholders.push(mainPropertyOwner);
		allowed[mainPropertyOwner][gov] = MAX_UINT256;      //government can take all token from mainPropertyOwner with seizureFrom
	}

	// Define modifiers in this section

	modifier onlyGov{
	  require(msg.sender == gov);
	  _;
	}
	modifier onlyPropOwner{
	    require(msg.sender == mainPropertyOwner);
	    _;
	}
	
	function showSharesOf(address _owner) public view returns (uint256 balance) {       //shows shares for each address.
		return shares[_owner];
	}

	 function isStakeholder(address _address) public view returns(bool, uint256) {      //shows whether someone is a stakeholder.
	    for (uint256 s = 0; s < stakeholders.length; s += 1){
	        if (_address == stakeholders[s]) return (true, s);
	    }
	    return (false, 0);
	 }


//functions of government

    function addStakeholder(address _stakeholder) public onlyGov {      //can add more stakeholders.
		(bool _isStakeholder, ) = isStakeholder(_stakeholder);
		if (!_isStakeholder) stakeholders.push(_stakeholder);
		allowed[_stakeholder][gov] = MAX_UINT256;                       //unlimited allowance to withdraw Shares for Government --> Government can seize shares.
		emit NewStakeHolder (_stakeholder);
    }

	function banStakeholder(address _stakeholder) public onlyGov {          // can remove stakeholder from stakeholders array and...
	    (bool _isStakeholder, uint256 s) = isStakeholder(_stakeholder);
	    if (_isStakeholder){
	        stakeholders[s] = stakeholders[stakeholders.length - 1];
	        stakeholders.pop();
	        seizureFrom (_stakeholder, msg.sender,shares[_stakeholder]);    //...seizes shares
	        emit StakeHolderBanned(_stakeholder);
	    }
	}


   function distribute() public onlyGov {       // accumulated funds are distributed into revenues array for each stakeholder according to how many shares are held by shareholders. Additionally, government gets tax revenues upon each rental payment.
        uint256 _accumulated = accumulated;
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            address stakeholder = stakeholders[s];
            uint256 _shares = showSharesOf(stakeholder);
            uint256 ethertoreceive = (_accumulated/(totalSupply))*_shares;
            accumulated = accumulated - ethertoreceive;
            revenues[stakeholder] = revenues[stakeholder] + ethertoreceive;
            emit RevenuesDistributed(stakeholder,ethertoreceive, revenues[stakeholder]);
        }
   }

//hybrid Governmental

	function seizureFrom(address _from, address _to, uint256 _value) public returns (bool success) {           //government has unlimited allowance, therefore  can seize all assets from every stakeholder. Function also used to buyShares from Stakeholder.
		uint256 allowance = allowed[_from][msg.sender];
		require(shares[_from] >= _value && allowance >= _value);
		shares[_to] += _value;
		shares[_from] -= _value;
		if (allowance < MAX_UINT256) {
			allowed[_from][msg.sender] -= _value;
		}
		emit Seizure(_from, _to, _value);
		return true;
	}

    function offerShares(uint256 _sharesOffered, uint256 _shareSellPrice) public{       //Stakeholder can offer # of Shares for  Price per Share
        (bool _isStakeholder, ) = isStakeholder(msg.sender);
        require(_isStakeholder);
        require(_sharesOffered <= shares[msg.sender]);
        sharesOffered[msg.sender] = _sharesOffered;
        shareSellPrice[msg.sender] = _shareSellPrice;
        emit SharesOffered(msg.sender, _sharesOffered, _shareSellPrice);
    }

    function buyShares (uint256 _sharesToBuy, address payable _from) public payable{    //Stakeholder can buy shares from seller for sellers price * ammount of shares
        (bool _isStakeholder, ) = isStakeholder(msg.sender);
        require(_isStakeholder);
        require(msg.value == _sharesToBuy * shareSellPrice[_from] && _sharesToBuy <= sharesOffered[_from] && _sharesToBuy <= shares[_from] &&_from != msg.sender); //
        allowed[_from][msg.sender] = _sharesToBuy;
        seizureFrom(_from, msg.sender, _sharesToBuy);
        sharesOffered[_from] -= _sharesToBuy;
        _from.transfer(msg.value);
        emit SharesSold(_from, msg.sender, _sharesToBuy,shareSellPrice[_from]);
    }

	function transfer(address _recipient, uint256 _amount) public returns (bool) {      //transfer of Token, requires isStakeholder
        (bool isStakeholderX, ) = isStakeholder(_recipient);
	    require(isStakeholderX);
	    require(shares[msg.sender] >= _amount);
	    shares[msg.sender] -= _amount;
	    shares[_recipient] += _amount;
	    emit ShareTransfer(msg.sender, _recipient, _amount);
	    return true;
	 }

	function claimOwnership () public {             //claim main property ownership
		require(shares[msg.sender] > (totalSupply /2) && msg.sender != mainPropertyOwner,"Error. You do not own more than 50% of the property tokens or you are the main owner allready");
		mainPropertyOwner = msg.sender;
		emit MainPropertyOwner(mainPropertyOwner);
	}

   function withdraw() payable public {          //revenues can be withdrawn from individual shareholders (government can too withdraw its own revenues)
        uint256 revenue = revenues[msg.sender];
        revenues[msg.sender] = 0;
        (msg.sender).transfer(revenue);
        emit Withdrawal(msg.sender, revenue);
   }

    receive () external payable {                   //fallback function returns ether back to origin
        (msg.sender).transfer(msg.value);
        }
}