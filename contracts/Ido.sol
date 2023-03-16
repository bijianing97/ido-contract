// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";

struct UserInfo {
    uint256 left;
    uint256 latestTimestamp;
}

contract Ido is Context {
    using SafeERC20 for ERC20;

    uint256 public price;

    uint256 public startAt;

    uint256 public endAt;

    uint256 public duration;

    uint256 public softCap;

    uint256 public hardCap;

    uint256 public percentOfRelease;

    ERC20 public myToken;

    ERC20 public idoToken;

    address public dev;

    uint256 public initAt;

    bool public initialized = false;

    uint256 public totalShares;

    mapping(address => uint256) public sharesOf;
    mapping(address => UserInfo) public userInfo;

    constructor(
        uint _price,
        uint _startAt,
        uint _endAt,
        uint _softCap,
        uint _hardCap,
        uint _duration,
        uint32 _percentOfRelease,
        ERC20 _myToken,
        ERC20 _idoToken
    ) {
        require(
            _price > 0 &&
                _startAt > 0 &&
                _endAt > 0 &&
                _softCap > 0 &&
                _hardCap > _softCap &&
                _percentOfRelease > 0 &&
                _percentOfRelease <= 100,
            "Invalid params"
        );

        price = _price;
        startAt = _startAt;
        endAt = _endAt;
        softCap = _softCap;
        hardCap = _hardCap;
        duration = _duration;
        percentOfRelease = _percentOfRelease;
        myToken = _myToken;
        idoToken = _idoToken;
        dev = _msgSender();
    }

    modifier onlyDev() {
        require(_msgSender() == dev, "Not dev");
        _;
    }

    modifier buyable() {
        require(
            !initialized &&
                block.timestamp >= startAt &&
                block.timestamp < endAt,
            "Not buyable"
        );
        _;
    }

    modifier initializable() {
        require(
            !initialized && initAt == 0 && block.timestamp >= endAt,
            "Not initializable"
        );
        _;
        initialized = true;
        initAt = block.timestamp;
    }

    modifier claimable() {
        require(
            initialized && block.timestamp > initAt && totalShares >= softCap,
            "Not claimable"
        );
        _;
    }

    modifier withdrawable() {
        require(
            initialized && block.timestamp > initAt && totalShares < softCap,
            "Not withdrawable"
        );
        _;
    }

    function getTotalSupply() public view returns (uint256) {
        if (totalShares >= hardCap) {
            return hardCap;
        } else {
            return (totalShares * 1e18) / price;
        }
    }

    function getPhase() external view returns (uint8) {
        if (block.timestamp < startAt) {
            return 0;
        } else if (block.timestamp >= startAt && block.timestamp < endAt) {
            return 1;
        } else {
            if (!initialized) {
                return 2;
            } else if (totalShares >= softCap) {
                return 3;
            } else {
                return 4;
            }
        }
    }

    function estimateBuy(uint256 amount) external view returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        uint256 _totalShares = totalShares + amount;
        if (_totalShares >= hardCap) {
            return (amount * hardCap * 1e18) / _totalShares / price;
        } else {
            return (amount * 1e18) / price;
        }
    }

    function buy(uint256 amount) external buyable {
        require(amount > 0, "invalid amount");
        idoToken.safeTransferFrom(_msgSender(), address(this), amount);
        totalShares += amount;
        sharesOf[_msgSender()] += amount;
    }

    function initialize() external initializable {
        uint256 finalCap;
        if (totalShares >= hardCap) {
            finalCap = hardCap;
        } else if (totalShares >= softCap) {
            finalCap = totalShares;
        } else {
            return;
        }
        uint256 _totalSupply = (finalCap * 1e18) / price;
        idoToken.safeTransfer(dev, idoToken.balanceOf(address(this)));
        // myToken.mint(address(this), _totalSupply);
    }

    function _estimateTotalMytokenFirstTime(
        address user
    )
        private
        view
        returns (uint256 immediaReleased, uint256 total, uint256 refunded)
    {
        if (totalShares >= hardCap) {
            uint256 amount = (sharesOf[user] * hardCap) / totalShares;
            total = (amount * 1e18) / price;
            refunded = sharesOf[user] - amount;
        } else {
            total = (sharesOf[user] * 1e18) / price;
        }
        immediaReleased = (total * percentOfRelease) / 10000;
    }

    function estimateClaim(
        address user
    )
        external
        view
        returns (uint256 total, uint256 refunded, uint256 released)
    {
        uint256 lastestTimestamp;
        uint256 immediateReleased;
        UserInfo memory info = userInfo[user];
        if (info.latestTimestamp == 0) {
            (
                immediateReleased,
                total,
                refunded
            ) = _estimateTotalMytokenFirstTime(user);
            lastestTimestamp = initAt;
        } else {
            lastestTimestamp = info.latestTimestamp;
            total = info.left;
        }
        if (initAt > 0) {
            uint256 endTimestamp = initAt + duration;
            if (
                lastestTimestamp < block.timestamp &&
                block.timestamp < endTimestamp
            ) {
                released =
                    immediateReleased +
                    ((total - immediateReleased) *
                        (block.timestamp - lastestTimestamp)) /
                    (endTimestamp - lastestTimestamp);
                if (released > total) {
                    released = total;
                }
            } else if (
                lastestTimestamp < endTimestamp &&
                block.timestamp >= endTimestamp
            ) {
                released = total;
            }
        }
    }

    function claim() external claimable {
        uint256 total;
        uint256 refunded;
        uint256 released;
        uint256 lastestTimestamp;
        uint256 immediateReleased;
        UserInfo memory info = userInfo[_msgSender()];

        if (info.latestTimestamp == 0) {
            (
                immediateReleased,
                total,
                refunded
            ) = _estimateTotalMytokenFirstTime(_msgSender());
            lastestTimestamp = initAt;
            delete sharesOf[_msgSender()];
        } else {
            lastestTimestamp = info.latestTimestamp;
            total = info.left;
        }

        uint256 endTimestamp = initAt + duration;
        if (
            lastestTimestamp < block.timestamp && block.timestamp < endTimestamp
        ) {
            released =
                immediateReleased +
                ((total - immediateReleased) *
                    (block.timestamp - lastestTimestamp)) /
                (endTimestamp - lastestTimestamp);
            if (released > total) {
                released = total;
            }

            info.latestTimestamp = block.timestamp;
        } else if (
            lastestTimestamp < endTimestamp && block.timestamp >= endTimestamp
        ) {
            released = total;
            info.latestTimestamp = endTimestamp;
        }
        info.left = total - released;
        if (released > 0) {
            uint256 max = myToken.balanceOf(address(this));
            myToken.transfer(_msgSender(), released > max ? max : released);
        }

        if (refunded > 0) {
            uint256 max = idoToken.balanceOf(address(this));
            idoToken.safeTransfer(
                _msgSender(),
                max < refunded ? max : refunded
            );
        }
    }

    function withdraw() external withdrawable {
        uint256 shares = sharesOf[_msgSender()];
        require(shares > 0, "No shares");
        uint256 max = idoToken.balanceOf(address(this));
        idoToken.safeTransfer(_msgSender(), max < shares ? max : shares);
        delete sharesOf[_msgSender()];
    }
}
