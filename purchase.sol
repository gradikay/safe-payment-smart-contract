// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

// ----------------------------------------------------------------------------
/// @author Gradi Kayamba
/// @title Purchase items with ether
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
/// @title Context : Information about sender, and value of the transaction.
// ----------------------------------------------------------------------------
abstract contract Context {
    /// @dev Returns information about the sender of the transaction.
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    /// @dev Returns information about the value of the transaction.
    function _msgValue() internal view virtual returns (uint256) {
        return msg.value;
    }
}

// ----------------------------------------------------------------------------
/// @title Purchase : Contract facilitating purchases using ether.
//  This contract uses the combination of  escrow, locked, and contribution 
//  to successfully track, and enable or disable transactions.
//  - escrow        : helps track the seller and buyer combined eth funds 
//                    base on the transaction id.
//  - locked        : helps lock transaction based on certain condition to 
//                    disable the buyer or the seller for withdrawing their funds.
//  - contribution  : helps track each seller and buyer ether funds for transfers. 
// ----------------------------------------------------------------------------
contract Purchase is Context {
    // Define public constant variables.
    address payable public founder; // Founder of the contract.
    address payable public deposit; // Deposit address for ehter fee.
    uint256 public fee;             // Fee for using the contract
    // Escrow help track transactions based on the transaction id
    // escrow[][][]       : uses the seller's and buyer's address as a reference.
    mapping(uint256 => mapping(address => mapping(address => uint256))) escrow;
    // locked[][][]       : Locks transaction on the order based on the transaction id.
    mapping(uint256 => mapping(address => mapping(address => bool))) locked;
    // contribution[][][] : Tracks each party's contributed funds based on the transaction id.
    mapping(uint256 => mapping(address => uint256)) contribution;

    // Set the follow value on contruction:
    // founder's address, deposit address, and fee amount.
    constructor(address payable _deposit) {
        founder = payable(_msgSender());
        deposit  = _deposit;
        fee = 100;
    }
    
    /**
     * @dev Triggers on any successful call to order().
     * @param _seller : The address selling the item.
     * @param _buyer : The address buying the item.
     * @param _id : The transaction id for the item.
     */
    event Order(address _seller, address _buyer, uint256 _id);
    /// Triggers on any successful call to cancel().
    event Cancel(address _seller, address _buyer, uint256 _id);
    /// Triggers on any successful call to unlock().
    event Unlock(address _seller, address _buyer, uint256 _id);
    /// Triggers on any successful call to comfirm().
    event Comfirm(address _seller, address _buyer, uint256 _id);
    /// Triggers on any successful call to instantPay().
    event InstantPay(address _seller, address _buyer, uint256 _id);
    
    /// You are not authorized to call this function.
    error OnlyBy();
    /// Withdraws are not locked.
    error WithdrawUnlocked();
    /// Withdraws are locked.
    error WithdrawLocked();
    /// The amount must be greater than (0) zero.
    error NoZero();
    /// Failed to transfer the funds, aborting.
    error FailedTransfer();
    /// Zero address not allowed.
    error NoneZero();

    /// @dev Makes a function callable only when the _owner is not a zero-address.
    modifier noneZero(address _recipient){
        if (_recipient == address(0))
            revert NoneZero();
        _;
    }
    /// @dev Makes a function callable only by _sender.
    modifier onlyBy(address _sender) {
        if (_msgSender() != _sender)
            revert OnlyBy();
        _;
    }
    /// @dev Makes a function callable only when _amount is more than (0) zero.
    modifier noZero(uint256 _amount) {
        if (_amount <= 0)
            revert NoZero();
        _;
    }
    /// @dev Makes a function callable only when locked[][][] is false.
    modifier whenUnlocked(address _seller, address _buyer, uint256 _id) {
        if (locked[_id][_seller][_buyer] == true)
            revert WithdrawLocked();
        _;
    }
    /// @dev Makes a function callable only when locked[][][] is true.
    modifier whenLocked(address _seller, address _buyer, uint256 _id) {
        if (locked[_id][_seller][_buyer] == false)
            revert WithdrawUnlocked();
        _;
    }
    /// @dev Makes a function callable only by _buyer or _seller.
    modifier onlyBoth(address _seller, address _buyer) {
        require(_msgSender() == _buyer || _msgSender() == _seller);
        _;
    }

    /**
     * @notice Transfers ether to the contract for order _id.
     * @notice Both seller and buyer have to send ether to the contract as escrow.
     * @notice This function is first called by _buyer only when unlocked,
     * @notice then called by _seller to lock it (the order).
     * @notice callable only by _buyer or _seller of order _id
     * @param _seller : The address selling the item.
     * @param _buyer : The address buying the item.
     * @param _id : The transaction id for the item.
     * @return success
     */
    function order(address payable _seller, address payable _buyer, uint256 _id)
    public
    payable
    onlyBoth(_buyer, _seller)
    whenUnlocked(_seller, _buyer, _id)
    returns (bool success)
    {
        // Add ether to escrow.
        escrow[_id][_seller][_buyer] += _msgValue();
        // Set ether contribution for _msgSender().
        contribution[_id][_msgSender()] = _msgValue();
        
        // If the caller is _seller lock the order because
        // the order is being processed.
        if(_msgSender() == _seller) {
            // set locked[][][] to true.
            locked[_id][_seller][_buyer] = true;
        }
        
        // See {event Order(...)}
        emit Order(_seller, _buyer, _id);
        
        // Returns true on success.
        return true;
    }
 
    /**
     * @notice Confirm that you (_buyer) received the item.
     * @notice This will transfer the locked ether to the _seller, the founder, and you (_buyer).
     * @notice callable only by _buyer
     * @notice then called by the seller to lock it (the order).
     * @param _seller : The address selling the item.
     * @param _buyer : The address buying the item.
     * @param _id : The transaction id for the item.
     */
    function confirm(address payable _seller, address _buyer, uint256 _id)
    onlyBy(_buyer)
    whenLocked(_seller, _buyer, _id)
    noZero(contribution[_id][_msgSender()])
    public 
    {
        // NOTE - Always check balance first before transaction.
        // Check _buyer's balance.
        uint _buyerFund = contribution[_id][_msgSender()];
        // Check _seller's balance.
        uint _sellerFund = contribution[_id][_seller];
        
        // Set _buyer contribution to 0.
        contribution[_id][_msgSender()] = 0;
        // Set _seller contribution to 0.
        contribution[_id][_seller] = 0;
        // Set _seller and _buyer escrow _id to 0.
        escrow[_id][_seller][_buyer] = 0;
        
        // Set transaction fee.
        uint256 payFee = (_sellerFund * 100) * fee / 1000000; // whatever % (fee percentage) will go toward the payFee
        
        // The buyer has to put (2 x ether) to the escrow and the seller only (1 x ether)
        // To allocate the funds correctly, with have to criss-cross the funds.
        // Thus sending the buyer's fund to the seller and seller's fund to the buyer.
        // Transfer seller's funds to the buyer.
        (bool successToSeller, ) = _seller.call{value: (_buyerFund - payFee)}("");
        // Transfer buyer's funds to the seller.
        (bool successToBuyer,  ) = _buyer.call{value: _sellerFund}("");
        // Transfer fee to the deposit of the founder.
        (bool successToFounder,) = deposit.call{value: payFee}("");
        
        // Check that the transfer is successful
        if(!successToSeller && !successToBuyer && !successToFounder) revert FailedTransfer();
        // require(successToSeller && successToBuyer && successToFounder, "Failed to transfer the funds, aborting.");
        
        // See {event Comfirm(...)}
        emit Comfirm(_seller, _buyer, _id);
    }
 
    /**
     * @notice This function refunds ether to _msgSender() (_buyer or _seller) for order _id.
     * @notice callable only when order is unlocked and contribution is not (0) zero.
     * @notice callable only by _buyer or _seller of order _id
     * @param _seller : The address selling the item.
     * @param _buyer : The address buying the item.
     * @param _id : The transaction id for the item.
     */
    function cancel(address _seller, address _buyer, uint256 _id)
    public 
    noZero(contribution[_id][_msgSender()])
    whenUnlocked(_seller, _buyer, _id)
    onlyBoth(_buyer, _seller)
    {
        // NOTE - Always check balance first before transaction.
        // Check sender's balance.
        uint _amount = contribution[_id][_msgSender()];
        
        // Set sender's contribution to 0.
        contribution[_id][_msgSender()] = 0;
        // Decrease escrow by _amount.
        escrow[_id][_seller][_buyer] -= _amount;
        // Transfer ether to sender.
        (bool success,  ) = payable(_msgSender()).call{value: _amount}("");
        
        // Check that the transfer is successful
        if(!success) revert FailedTransfer();
        
        // See {event Cancel(...)}
        emit Cancel(_seller, _buyer, _id);
    }
    
    /**
     * @notice This function unlockes transaction for order _id.
     * @notice callable only by _seller and when locked
     * @param _seller : The address selling the item.
     * @param _buyer : The address buying the item.
     * @param _id : The transaction id for the item.
     * @return success
     */
    function unlock(address _seller, address _buyer, uint256 _id) 
    public 
    onlyBy(_seller)
    whenLocked(_seller, _buyer, _id)
    returns (bool success) 
    {
        // Set locked to false to allow transactions/withdraws for order _id.
        locked[_id][_seller][_buyer] = false;
        
        // See {event Unlock(...)}
        emit Unlock(_seller, _buyer, _id);
        
        // Returns true on success.
        return true;
    }
    
    /**
     * @notice Changes fees.
     * @notice Callable by the founder only.
     * @notice Callable only by a none-zero address.
     * @param _newFee : The new fee amount.
     */
    function changeFee(uint256 _newFee) 
    onlyBy(founder)
    noneZero(_msgSender())
    public 
    returns (bool success) 
    {
        // Change amount from fee to _newFee.
        fee = _newFee;
        
        // Returns true on success.
        return true;
    }
    
    /**
     * @notice Transfers ether from sender address to _recipient address.
     * @notice Callable only by a none-zero address.
     * @param _recipient : The address receiving ether.
     */
    function instantPay(address payable _recipient) payable public noneZero(_recipient) {

        // Transfer ether to _recipient.
        (bool success,  ) = _recipient.call{value: _msgValue()}("");
        
        // Check that the transfer is successful
        if(!success) revert FailedTransfer();
        
        // See {event InstantPay(...)}
        emit InstantPay(_msgSender(), _recipient, _msgValue());
    }
    
    
    /**
     * @notice Returns the amount of ether in escrow order _id.
     * @return remaining 000
     */
    function escrowOf(address _seller, address _buyer, uint256 _id) public view returns (uint256 remaining) {
        // Returns spender's allowance balance.
        return escrow[_id][_seller][_buyer];
    }
    
    /**
     * @notice Returns the locked status of a order _id.
     * @return pending true/false
     */
    function lockedOf(address _seller, address _buyer, uint256 _id) public view returns (bool pending) {
        // Returns spender's allowance balance.
        return locked[_id][_seller][_buyer];
    }
    
    /**
     * @notice Returns the amount of ether contribution of an order _id.
     * @return balance 000
     */
    function contributionOf(address _sender, uint256 _id) public view returns (uint256 balance) {
        // Returns spender's allowance balance.
        return contribution[_id][_sender];
    }
}
