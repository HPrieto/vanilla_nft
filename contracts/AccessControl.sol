pragma solidity >=0.4.22 <0.9.0;

/// @title A contract for managing special access privileges.
/// @author Heriberto Prieto
contract AccessControl {

  /// @dev Heriberto Prieto
  event ContractUpgrade(address newContract);

  // The addresses of the accounts (or contracts) that can execute actions within each roles;
  address public ceoAddress;
  address public cfoAddress;
  address public cooAddress;

  // The addresses of the accounts is paused. When that is true, most actions are blocked.
  bool public paused = false;

  /// @dev Access modifier for CEO-only functionality
  modifier onlyCEO() {
    require(msg.sender == ceoAddress);
    _;
  }

  /// @dev Access modifier for CFO-only functionality
  modifier onlyCFO() {
    require(msg.sender == cfoAddress);
    _;
  }

  /// @dev Access modifier for COO-only functionality
  modifier onlyCOO() {
    require(msg.sender == cooAddress);
    _;
  }

  modifier onlyCLevel() {
    require(
        msg.sender == ceoAddress ||
        msg.sender == cfoAddress ||
        msg.sender == cooAddress
    );
    _;
  }

  /// @dev Assigns a new address to act as the CEO. Only available to the current CEO.
  /// @param _newCEO The address of the new CEO.
  function setCEO(address _newCEO) external onlyCEO {
    require(_newCEO != address(0));

    ceoAddress = _newCEO;
  }

  /// @dev Assigns a new address to act as the CFO. Only available to the current CEO.
  /// @param _newCFO The address of the new CFO.
  function setCFO(address _newCFO) external onlyCEO {
    require(_newCFO != address(0));

    cfoAddress = _newCFO;
  }

  /// @dev Assigns a new address to act as the COO. Only available to the current CEO.
  /// @param _newCOO The address of the new COO.
  function setCOO(address _newCOO) external onlyCEO {
    require(_newCOO != address(0));

    cooAddress = _newCOO;
  }

  /*** Pausable functionality adapted from OpenZeppelin ***/

  /// @dev Modifier to allow actions only when the contract IS NOT paused.
  modifier whenNotPaused() {
    require(!paused);
    _;
  }

  /// @dev Modifier to allow actions only when the contract IS paused.
  modifier whenPaused() {
    require(paused);
    _;
  }

  /// @dev Called by any "C-Level" role to pause the contract. Used only when
  ///  a bug or exploited is detected and we need to limit damage.
  function pause() external onlyCLevel whenNotPaused {
    paused = true;
  }

  /// @dev Unpauses the smart contract. Can only be called by the CEO, since
  ///  one reason we may pause the contract is when CFO or COO accounts are
  ///  compromised.
  /// @notice This is public rather than external so it can be called by
  ///  derived contracts.
  function unpause() public onlyCEO whenPaused {
    // can't pause if contract was upgraded
    paused = false;
  }
}
