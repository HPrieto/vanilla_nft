pragma solidity >=0.4.22 <0.9.0;

import "./AccessControl.sol";

/// @title Base contract. Holds all common structs, events, and base variables.
/// @author Duskayame@gmail.com
contract Base is AccessControl {
  /*** EVENTS ***/

  /// @dev The Birth event is fired whenever a new token comes into existence. This obviously
  ///  includes any time a cat is created through the giveBirth method, but it is also called
  ///  when a new gen0 token is created.
  event Birth(address owner, uint256 tokenId, uint256 matronId, uint256 sireId, uint256 traits);

  /// @dev Transfer event as defined in current draft of ERC721. Emitted every time
  ///  ownership is assigned.
  event Transfer(address from, address to, uint256);

  /*** DATA TYPES ***/

  /// @dev The main struct. Every NFT is represented by a copy
  ///  of this structure, so great care was taken to ensure that it fits neatly into
  ///  exactly two 256-bit words. Note that the order of the members in this structure
  ///  is important because of the byte-packing rules used by Ethereum.
  struct NFT {
    // The NFT's genetic code is packed into these 256-bits and will never change.
    uint256 traits;

    // The timestamp from the block when this NFT came into existence.
    uint64 createTime;

    // The minimum timestamp after which this token can engage in breeding
    // activities again. This same timestamp is used for the pregnancy
    // timer (for matrons) as well as the siring cooldown.
    uint64 cooldownEndBlock;

    // The ID of the parents of this kitty, set to 0 for gen0 tokens.
    // Note that using 32-bit unsigned integers limits us to a "mere"
    // 4 billion tokens. This number might seem small until you realize
    // that Ethereum currently has a limit of about 500 million
    // transactions per year! So, this definitely won't be a problem
    // for several years (even as Ethereum learns to scale).
    uint32 matronId;
    uint32 sireId;

    // Set to the ID of the sire token for matrons that are pregnant,
    // zero otherwise. A non-zero value here is how we know a token
    // is pregnant. Used to retrieve the genetic material for the new
    // kitten when the birth transpires.
    uint32 siringWithId;

    // Set to the index in the cooldown array (see below) that represents
    // the current cooldown duration for this NFT. This starts at zero
    // for gen0 NFTs, and is initialized to floor(generation/2) for others.
    // Incremented by one for each successful breeding action, regardless
    // of whether this NFT is acting as matron or sire.
    uint16 cooldownIndex;

    // The "generation number" of this NFT. NFTs minted by this contract
    // for sale are called "gen0" adn have a generation number of 0. The
    // generation number of all other NFTs is the larger of the two generation
    // numbers of their parents, plus one.
    // (i.e. max(matron.generation, sire.generation) + 1)
    uint16 generation;
  }

  /*** CONSTANTS ***/
  /// @dev A lookup table indicating the cooldown duration after any successful
  ///  breeding action, called "pregnancy time" for matrons and "siring cooldown"
  ///  for sires. Designed such that the cooldown roughly doubles each time a NFT
  ///  is bred, encouraging owners not to just keep breeding the same NFT over
  ///  and over again. Caps out at one week (a NFT can breed an unbounded number
  ///  of times, and the maximum cooldown is always seven days).
  uint32[14] public cooldowns = [
      uint32(1 minutes),
      uint32(2 minutes),
      uint32(5 minutes),
      uint32(10 minutes),
      uint32(30 minutes),
      uint32(1 hours),
      uint32(2 hours),
      uint32(4 hours),
      uint32(8 hours),
      uint32(16 hours),
      uint32(1 days),
      uint32(2 days),
      uint32(4 days),
      uint32(7 days)
  ];

  // An approximation of currently how many seconds are in between blocks.
  uint256 public secondsPerBlock = 15;

  /*** STORAGE ***/

  /// @dev An array containing the NFT struct for all NFTs in existence. The ID
  ///  of each NFT is actually an index into this array. Note that ID 0 is a negaNFT,
  ///  NFT ID 0 is invalid.
  NFT[] tokens;

  /// @dev A mapping from NFT IDs to the address that owns them. All NFTs have
  ///  some valid owner address, even gen0 NFTs are created with a non-zero owner.
  mapping (uint256 => address) public tokenIndexToOwner;

  /// @dev A mapping from owner address to count of tokens that address owns.
  ///  Used internally inside balanceOf() to resolve ownership count.
  mapping (address => uint256) ownershipTokenCount;

  /// @dev A mapping from NFTIDs to an address that has been approved to call
  ///  transferFrom(). Each NFT can only have one approved address for transfer
  ///  at any time. A zero value means no approval is outstanding.
  mapping (uint256 => address) public tokenIndexToApproved;

  /// @dev A mapping from TokenIDs to an address that has been approved to use
  ///  this NFT for siring via breedWith(). Each NFT can only have one approved
  ///  address for siring at any time. A zero value means no approval is outstanding.
  mapping (uint256 => address) public sireAllowedToAddress;

  /// @dev The address of the ClockAuction contract that handles sales of Tokens. This
  ///  same contract handles both peer-to-peer sales as well as the gen0 sales which are
  ///  initiated every 15 minutes.
  //SaleClockAuction public saleAuction;

  /// @dev The address of a custom ClockAuction subclassed contract that handles siring
  ///  auctions. Needs to be separate from saleAuction becuase the actions taken on success
  ///  after a sales and siring auction are quite different.
  //SiringClockAuction public siringAuction;

  /// @dev Assigns ownership of a specific NFT to an address.
  function _transfer(address _from, address _to, uint256 _tokenId) internal {
    // Since the number of tokens is capped to 2^32 we can't overflow this
    ownershipTokenCount[_to]++;
    // transfer ownership
    tokenIndexToOwner[_tokenId] = _to;
    // When creating new tokens _from is 0x0, but we can't account that address.
    if (_from != address(0)) {
      ownershipTokenCount[_from]--;
      // once the token is transferred also clear sire allowances
      delete sireAllowedToAddress[_tokenId];
      // clear any previously approved ownership exchange
      delete tokenIndexToApproved[_tokenId];
    }
    // Emit the transfer event.
    emit Transfer(_from, _to, _tokenId);
  }

  /// @dev An internal method that creates a new token and stores it. This
  ///  method doesn't do any checking and should only be called when the
  ///  input data is known to be valid. Will generate both a Birth event
  ///  and a Transfer event.
  /// @param _matronId The token ID of the matron of this token (zero for gen0)
  /// @param _sireId The token ID of the sire fo this token (zero for gen0)
  /// @param _generation The generation number of this token, must be computed by caller.
  /// @param _traits The NFT's genetic code.
  /// @param _owner The initial owner of this token, must be non-zero (except for the unToken, ID 0)
  function _createToken(
    uint256 _matronId,
    uint256 _sireId,
    uint256 _generation,
    uint256 _traits,
    address _owner
  )
    internal
    returns (uint)
  {
    // These requires are not strictly necessary, our calling code should make
    // sure that these conditions are never broken. However! _createToken() is already
    // an expensive call (for storage), and it doesn't hurt to be especially careful
    // to ensure our data structures are always valid.
    require(_matronId == uint256(uint32(_matronId)));
    require(_sireId == uint256(uint32(_sireId)));
    require(_generation == uint256(uint16(_generation)));

    // New token starts with the same cooldown as parent gen/2
    uint16 cooldownIndex = uint16(_generation / 2);
    if (cooldownIndex > 13) {
      cooldownIndex = 13;
    }

    NFT memory _token = NFT({
      traits: _traits,
      createTime: uint64(now),
      cooldownEndBlock: 0,
      matronId: uint32(_matronId),
      sireId: uint32(_sireId),
      siringWithId: 0,
      cooldownIndex: cooldownIndex,
      generation: uint16(_generation)
    });
    uint256 newTokenId = tokens.push(_token) - 1;

    // It's probably never going to happen, 4 billion tokens is A LOT, but
    // let's just be 100% sure we never let this happen.
    require(newTokenId == uint256(uint32(newTokenId)));

    // emit the birth event.
    emit Birth(
      _owner,
      newTokenId,
      uint256(_token.matronId),
      uint256(_token.sireId),
      _token.traits
    );

    // This will assign ownership, and also emit the Transfer event as
    // per ERC721 draft
    _transfer(address(0), _owner, newTokenId);

    return newTokenId;
  }

  // Any C-level can fix how many seconds per block are currently observed.
  function setSecondsPerBlock(uint256 secs) external onlyCLevel {
    require(secs < cooldowns[0]);
    secondsPerBlock = secs;
  }
}
