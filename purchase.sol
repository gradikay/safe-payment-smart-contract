// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// ----------------------------------------------------------------------------
/// @author Gradi Kayamba
/// @title Purchase items with ether
/// @dev notice contract gas cost (1,718,837 gas)
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
/// @title Context : Information about sender, and value of the transaction.
// ----------------------------------------------------------------------------
abstract contract Context {
    /// @dev Returns information about the sender of the transaction.
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

// ----------------------------------------------------------------------------
/// @title Purchase : Smart Contract facilitating purchases using ether.
//  This contract uses the mapping combination of `escrow`, `locked`,  
//  and `contribution` to track, and enable or disable transactions using `_id`, 
//  and `_seller` and `_buyer` addresses as a reference.
//  - escrow[_id][_seller][_buyer]      : Helps track the seller and buyer combined 
//                                        ether funds based on the transaction id.
//  - locked[_id][_seller][_buyer]      : Prevents the buyer and the seller from withdrawing 
//                                        their funds based on the transaction id.
//  - contribution[_id][_seller/_buyer] : Helps track seller or buyer ether fund to facilitate 
//                                        transfers based on the transaction id.
// ----------------------------------------------------------------------------
contract Purchase is Context {
    // Define public constant variables.
    address payable public founder; // Founder of the contract.
    address payable public deposit; // Deposit address for ether fee.
    uint256 public fee;             // Fee for using the contract
    // escrow[][][]     : Tracks both seller and buyer contributed funds.
    mapping(uint256 => mapping(address => mapping(address => uint256))) escrow;
    // locked[][][]     : Locks transactions (withdraws) on the order.
    mapping(uint256 => mapping(address => mapping(address => bool))) locked;
    // contribution[][] : Tracks each party's contributed funds.
    mapping(uint256 => mapping(address => uint256)) contribution;

    // Set the following value on construction:
    // founder's address, deposit address, and fee amount.
    constructor(address payable _deposit) {
        founder = payable(_msgSender());
        deposit  = _deposit;
        fee = 100;
    }
    
    /**
     * @dev Triggers on any successful call to order().
     * @param seller : The address selling the item.
     * @param buyer  : The address buying the item.
     * @param id     : The transaction id for the item.
     */
    event Order(address seller, address buyer, uint256 id, uint256 amount);
    /// Triggers on any successful call to cancel().
    event Withdraw(address seller, address buyer, uint256 id, uint256 amount);
    /// Triggers on any successful call to unlock().
    event Unlock(address seller, address buyer, uint256 id);
    /// Triggers on any successful call to comfirm().
    event Confirm(address seller, address buyer, uint256 id, uint256 buyerBalance, uint256 sellerBalance, uint256 fee);
    /// Triggers on any successful call to instantPay().
    event InstantPay(address seller, address buyer, uint256 amount);
    
    /// You are not authorized to call this function.
    error OnlyBy();
    /// The amount must be greater than (0) zero.
    error NoZero();
    /// Zero address not allowed.
    error NoneZero();
    /// Failed to transfer the funds, aborting.
    error FailedTransfer();
    /// Withdraws are locked.
    error WithdrawLocked();
    /// Withdraws are not locked.
    error WithdrawUnlocked();

    /// @dev Makes a function callable only when the _owner is not a zero-address.
    modifier noneZero(address _recipient){
        if (_recipient == address(0))
            revert NoneZero();
        _;
    }
    /// @dev Makes a function callable only by _authorized.
    modifier onlyBy(address _authorized) {
        if (_msgSender() != _authorized)
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
        require(_msgSender() == _seller || _msgSender() == _buyer);
        _;
    }

    /**
     * @dev Gas cost min (72761) - max (77000) 
     * @notice Transfers ether to the contract for order _id.
     * @notice Both seller and buyer have to send ether to the contract as escrow.
     * @notice This function is first called by _buyer only when unlocked,
     * @notice then called by _seller to lock it (the order).
     * @notice Callable only by _buyer or _seller of order _id.
     * @param _seller : The address selling the item.
     * @param _buyer  : The address buying the item.
     * @param _id     : The transaction id for the item.
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
        escrow[_id][_seller][_buyer] += msg.value;
        // Set ether contribution for _msgSender().
        contribution[_id][_msgSender()] = msg.value;
        
        // If the caller is _seller lock the order because
        // the order is being processed.
        if(_msgSender() == _seller) {
            // set locked[][][] to true.
            locked[_id][_seller][_buyer] = true;
        }
        
        // See {event Order(...)}
        emit Order(_seller, _buyer, _id, msg.value);
        
        // Returns true on success.
        return true;
    }
 
    /**
     * @dev Gas cost min (60805) - max (62000) 
     * @notice Confirm that you (_buyer) received the item.
     * @notice This will transfer the locked ether to the _seller, the founder, and you (_buyer).
     * @notice Callable only by _buyer.
     * @param _seller : The address selling the item.
     * @param _buyer  : The address buying the item.
     * @param _id     : The transaction id for the item.
     */
    function confirm(address payable _seller, address payable _buyer, uint256 _id)
    onlyBy(_buyer)
    whenLocked(_seller, _buyer, _id)
    noZero(contribution[_id][_msgSender()]) // Get amount contributed by _msgSender()
    public 
    {
        // NOTE - Always check balance first before transaction.
        // Check _buyer's balance.
        uint _buyerBalance  = contribution[_id][_msgSender()];
        // Check _seller's balance.
        uint _sellerBalance = contribution[_id][_seller];
        
        // Set _buyer contribution to 0.
        contribution[_id][_msgSender()] = 0;
        // Set _seller contribution to 0.
        contribution[_id][_seller]      = 0;
        // Set _seller and _buyer escrow to 0.
        escrow[_id][_seller][_buyer]    = 0;
        
        // Set transaction fee.
        // if fee = 100 then 1%; if fee = 30 then 0.3% ... and so on.
        // thus ~ ((balance * 100) * 30 / 10000) ~ 0.3% ~ will work!
        // and  ~ (balance * 0.3 / 100)          ~ 0.3% ~ will not work!
        uint256 _feeAmount = (_buyerBalance * 100) * fee / 1000000; // whatever % (fee percentage) will go toward the fee amount
        
        // The buyer has to put (2 x ether) to the escrow and the seller only (1 x ether)
        // To allocate the funds correctly, we have to criss-cross the funds.
        // Thus sending the buyer's fund to the seller and the seller's fund to the buyer.
        // Transfer buyer's funds to the seller.
        (bool successToSeller, ) = _seller.call{value: (_buyerBalance - _feeAmount)}("");
        // Transfer seller's funds to the buyer.
        (bool successToBuyer, )  =  _buyer.call{value: _sellerBalance}("");
        // Transfer fee to the deposit of the founder.
        (bool successToFounder,) = deposit.call{value: _feeAmount}("");
        
        // Check that the transfer is successful
        if(!successToSeller && !successToBuyer && !successToFounder) revert FailedTransfer();
        
        // See {event Comfirm(...)}
        emit Confirm(_seller, _buyer, _id, _sellerBalance, _buyerBalance - _feeAmount, _feeAmount);
    }
 
    /**
     * @dev Gas cost min (36575) - max (54000 !important)
     * @notice This function refunds ether to _msgSender() (_buyer or _seller) for order _id.
     * @notice Callable only when order is unlocked and contribution is not (0) zero.
     * @notice Callable only by _buyer or _seller for order _id
     * @param _seller : The address selling the item.
     * @param _buyer  : The address buying the item.
     * @param _id     : The transaction id for the item.
     */
    function withdraw(address _seller, address _buyer, uint256 _id)
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
        
        // See {event Withdraw(...)}
        emit Withdraw(_seller, _buyer, _id, _amount);
    }
    
    /**
     * @dev Gas cost min (26125) - max (28000) 
     * @notice This function unlocks transaction for order _id.
     * @notice Callable only by _seller and when locked
     * @param _seller : The address selling the item.
     * @param _buyer  : The address buying the item.
     * @param _id     : The transaction id for the item.
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
     * @dev Gas cost min (29125) - max (31000)
     * @notice Changes fees.
     * @notice Callable by the founder only.
     * @notice Callable only by a none-zero address.
     * @param _newFee : The new fee amount. (e.g. 100 is 1%, 30 is 0.3%, 5 is 0.05% ...)
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
     * @dev Gas cost min (33780) - max (35000) 
     * @notice Transfers ether from sender address to _recipient address.
     * @notice Callable only by a none-zero address.
     * @param _recipient : The address receiving ether.
     */
    function instantPay(address payable _recipient) payable public noneZero(_recipient) {

        // Transfer ether to _recipient.
        (bool success,  ) = _recipient.call{value: msg.value}("");
        
        // Check that the transfer is successful
        if(!success) revert FailedTransfer();
        
        // See {event InstantPay(...)}
        emit InstantPay(_msgSender(), _recipient, msg.value);
    }
    
    
    /**
     * @notice Returns the amount of ether of _seller and _buyer escrow for order _id.
     * @return remaining 000
     */
    function escrowOf(address _seller, address _buyer, uint256 _id) public view returns (uint256 remaining) {
        return escrow[_id][_seller][_buyer];
    }
    
    /**
     * @notice Returns the locked status for order _id of _seller and _buyer.
     * @return pending true/false
     */
    function lockedOf(address _seller, address _buyer, uint256 _id) public view returns (bool pending) {
        return locked[_id][_seller][_buyer];
    }
    
    /**
     * @notice Returns the amount of ether contribution of _sender for order _id.
     * @return balance 000
     */
    function contributionOf(address _sender, uint256 _id) public view returns (uint256 balance) {
        return contribution[_id][_sender];
    }
}
