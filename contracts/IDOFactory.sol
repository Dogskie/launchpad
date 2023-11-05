pragma solidity ^0.8.18;

import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./IDOPool.sol";
import "./IDOERC20Pool.sol";

contract IDOFactory is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20Burnable;
    using SafeERC20 for ERC20;

    uint256 public version = 2;

    ERC20Burnable public feeToken;
    address public feeWallet;
    uint256 public feeAmount;
    uint256 public burnPercent; // use this state only if your token is ERC20Burnable and has burnFrom method
    uint256 public divider;

    bool public onlyOwnerCreate = false;

    function setOnlyOwnerCreate(bool _onlyOwnerCreate) external onlyOwner {
        onlyOwnerCreate = _onlyOwnerCreate;
    }

    address[] public idoPools;

    event IDOCreated(
        address indexed owner,
        address idoPool,
        address indexed rewardToken,
        string tokenURI
    );

    event TokenFeeUpdated(address newFeeToken);
    event FeeAmountUpdated(uint256 newFeeAmount);
    event BurnPercentUpdated(uint256 newBurnPercent, uint256 divider);
    event FeeWalletUpdated(address newFeeWallet);

    constructor(
        ERC20Burnable _feeToken,
        uint256 _feeAmount,
        uint256 _burnPercent
    ){
        feeToken = _feeToken;
        feeAmount = _feeAmount;
        burnPercent = _burnPercent;
        divider = 100;
    }

    function getIdoPools() public view returns (address[] memory) {
      return idoPools;
    }

    function setFeeToken(address _newFeeToken) external onlyOwner {
        require(isContract(_newFeeToken), "New address is not a token");
        feeToken = ERC20Burnable(_newFeeToken);

        emit TokenFeeUpdated(_newFeeToken);
    }

    function setFeeAmount(uint256 _newFeeAmount) external onlyOwner {
        feeAmount = _newFeeAmount;

        emit FeeAmountUpdated(_newFeeAmount);
    }

    function setFeeWallet(address _newFeeWallet) external onlyOwner {
        feeWallet = _newFeeWallet;

        emit FeeWalletUpdated(_newFeeWallet);
    }

    function setBurnPercent(uint256 _newBurnPercent, uint256 _newDivider)
        external
        onlyOwner
    {
        require(_newBurnPercent <= _newDivider, "Burn percent must be less than divider");
        burnPercent = _newBurnPercent;
        divider = _newDivider;

        emit BurnPercentUpdated(_newBurnPercent, _newDivider);
    }

    function createIDO(
        ERC20 _rewardToken,
        IDOPool.FinInfo memory _finInfo,
        IDOPool.Timestamps memory _timestamps,
        IDOPool.DEXInfo memory _dexInfo,
        address _lockerFactoryAddress,
        string memory _metadataURL
    ) external {
        if (onlyOwnerCreate) {
            require(msg.sender == this.owner(), "Only owner can create IDOPool");
        }
        IDOPool idoPool =
            new IDOPool(
                _rewardToken,
                _finInfo,
                _timestamps,
                _dexInfo,
                _lockerFactoryAddress,
                _metadataURL
            );

        idoPool.transferOwnership(msg.sender);

        processIDOCreate(
            _rewardToken,
            address(idoPool),
            _finInfo.hardCap,
            _finInfo.tokenPrice,
            _finInfo.lpInterestRate,
            _finInfo.listingPrice,
            _metadataURL
        );
    }

    function createIDOERC20(
        ERC20 _rewardToken,
        ERC20 _payToken,
        IDOERC20Pool.FinInfo memory _finInfo,
        IDOERC20Pool.Timestamps memory _timestamps,
        string memory _metadataURL
    ) external {
        if (onlyOwnerCreate) {
            require(msg.sender == this.owner(), "Only owner can create IDOPool");
        }
        IDOERC20Pool idoPool =
            new IDOERC20Pool(
                _rewardToken,
                _payToken,
                _finInfo,
                _timestamps,
                _metadataURL
            );
        idoPool.transferOwnership(msg.sender);

        processIDOCreate(
            _rewardToken,
            address(idoPool),
            _finInfo.hardCap,
            _finInfo.tokenPrice,
            _finInfo.lpInterestRate,
            _finInfo.listingPrice,
            _metadataURL
        );
    }

    function processIDOCreate(
        ERC20 _rewardToken,
        address idoPoolAddress,
        uint256 hardCap,
        uint256 tokenPrice,
        uint256 lpInterestRate,
        uint256 listingPrice,
        string memory _metadataURL
    ) private {
        uint8 tokenDecimals = _rewardToken.decimals();

        uint256 transferAmount = getTokenAmount(hardCap, tokenPrice, tokenDecimals);

        if (lpInterestRate > 0 && listingPrice > 0) {
            transferAmount += getTokenAmount(hardCap * lpInterestRate / 100, listingPrice, tokenDecimals);
        }

        _rewardToken.safeTransferFrom(
            msg.sender,
            idoPoolAddress,
            transferAmount
        );

        idoPools.push(idoPoolAddress);

        emit IDOCreated(
            msg.sender,
            idoPoolAddress,
            address(_rewardToken),
            _metadataURL
        );


        if(feeAmount > 0){
            if (burnPercent > 0){
                uint256 burnAmount = feeAmount.mul(burnPercent).div(divider);

                feeToken.safeTransferFrom(
                    msg.sender,
                    feeWallet,
                    feeAmount.sub(burnAmount)
                );

                feeToken.burnFrom(msg.sender, burnAmount);
            } else {
                feeToken.safeTransferFrom(
                    msg.sender,
                    feeWallet,
                    feeAmount
                );
            }
        }
    }

    function getTokenAmount(uint256 ethAmount, uint256 oneTokenInWei, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        return (ethAmount / oneTokenInWei) * 10**decimals;
    }

    function isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

}