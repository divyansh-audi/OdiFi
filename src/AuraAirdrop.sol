// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.30;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
/**
 * @title AuraAirdrop
 * @author Divyansh Audichya
 * @notice This is the airdrop contract for the AuraPowerToken to be distributed to selected users.
 */

contract AuraAirdrop is EIP712 {
    /*///////////////////////////////////////
                   LIBRARIES
    ///////////////////////////////////////*/
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////
                   ERRORS
    ///////////////////////////////////////*/

    error AuraAirdrop__AirdropAlreadyClaimed();
    error AuraAirdrop__InvalidSignature();
    error AuraAirdrop__InvalidProof();

    /*///////////////////////////////////////
                STATE VAIRABLES
    ///////////////////////////////////////*/
    IERC20 private immutable i_airdropToken;
    bytes32 private immutable i_merkleRoot;
    mapping(address user => bool) private s_airdropClaimed;

    bytes32 private constant MESSAGE_TYPEHASH = keccak256("AirdropClaim(address account,uint256 amount)");

    /*///////////////////////////////////////
                TYPE DECLARATIONS
    ///////////////////////////////////////*/

    struct AirdropClaim {
        address account;
        uint256 amount;
    }

    /*///////////////////////////////////////
                   EVENTS
    ///////////////////////////////////////*/
    event Claimed(address indexed account, uint256 indexed amount);

    /*///////////////////////////////////////
                   FUNCTIONS
    ///////////////////////////////////////*/
    constructor(bytes32 merkleRoot, address airDropToken) EIP712("AuraAirdrop", "1.0.0") {
        i_merkleRoot = merkleRoot;
        i_airdropToken = IERC20(airDropToken);
    }

    /*///////////////////////////////////////
                EXTERNAL FUNCTIONS
    ///////////////////////////////////////*/
    /**
     * @notice This function :-
     * 1. Check if the airdrop is already claimed or not
     * 2. Check if the signature is valid
     * 3. Verify the merkle proof
     * 4. transfer the tokens to the address
     * @param _accountToClaimAirdrop account to send tokens
     * @param _amountOfAirdrop amount of tokens
     * @param _merkleProof merkle proof for that account
     * @param _v the v component of signature
     * @param _r the r component of signature
     * @param _s the s component of signature
     */
    function claim(
        address _accountToClaimAirdrop,
        uint256 _amountOfAirdrop,
        bytes32[] calldata _merkleProof,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        //CEI
        if (s_airdropClaimed[_accountToClaimAirdrop]) {
            revert AuraAirdrop__AirdropAlreadyClaimed();
        }

        if (
            !_isValidSignature(
                _accountToClaimAirdrop, getMessageHash(_accountToClaimAirdrop, _amountOfAirdrop), _v, _r, _s
            )
        ) {
            revert AuraAirdrop__InvalidSignature();
        }

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_accountToClaimAirdrop, _amountOfAirdrop))));

        if (!MerkleProof.verify(_merkleProof, i_merkleRoot, leaf)) {
            revert AuraAirdrop__InvalidProof();
        }

        s_airdropClaimed[_accountToClaimAirdrop] = true;
        emit Claimed(_accountToClaimAirdrop, _amountOfAirdrop);
        i_airdropToken.safeTransfer(_accountToClaimAirdrop, _amountOfAirdrop);
    }

    /**
     * @notice This function returns the digest which is hashStruct(message) which means:-
     * hashStruct(message)-> keccack256(typeHash || structData)),which can be futher be like :-
     * hashStruct(message)->keccack256(encode(MESSAGE_TYPEHASH,AirdropClaim({account;account,amount:amount}));
     * @param _account account to send the token
     * @param _amount amount of token
     */
    function getMessageHash(address _account, uint256 _amount) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(MESSAGE_TYPEHASH, AirdropClaim({account: _account, amount: _amount})))
        );
    }

    /*///////////////////////////////////////
                INTERNAL FUNCTIONS
    ///////////////////////////////////////*/

    /**
     * @notice Check of the `_signer` is the real signer by deriving the address using the digest and signature components.
     * @param _signer signer of the message
     * @param digest the hashStruct(messgae)
     * @param v the v component of signature
     * @param r the r component of signature
     * @param s the s component of signature
     */
    function _isValidSignature(address _signer, bytes32 digest, uint8 v, bytes32 r, bytes32 s)
        internal
        pure
        returns (bool)
    {
        (address recoveredAccount, /*RecoverError err*/, /*bytes32 errArg*/ ) = ECDSA.tryRecover(digest, v, r, s);
        return (_signer == recoveredAccount);
    }

    /*///////////////////////////////////////
                GETTER  FUNCTIONS
    ///////////////////////////////////////*/

    /**
     * @return address Address of the airdrop token
     */
    function getAirdropTokenAddress() public view returns (address) {
        return address(i_airdropToken);
    }

    /**
     * @return bytes32 Merkle root of the merkle tree
     */
    function getMerkleRoot() public view returns (bytes32) {
        return i_merkleRoot;
    }
}
