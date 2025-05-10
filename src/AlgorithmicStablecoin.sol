// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AlgorithmicStablecoin — ERC20 con suministro elástico "gons/fragments"
 * Inspirado en Ampleforth UFragments.
 */
contract AlgorithmicStablecoin is IERC20Metadata, Ownable {
    string public constant name        = "Virtual COP";
    string public constant symbol      = "VCOP";
    uint8  public constant decimals    = 18;

    // Total gons = 2^128 — mantiene precisión al escalar
    uint256 private constant TOTAL_GONS = type(uint256).max - (type(uint256).max % 1e24);
    uint256 private _totalSupply       = 1e24;               // 1 M tokens inicio
    uint256 private _gonsPerFragment   = TOTAL_GONS / _totalSupply;

    mapping(address => uint256) private _gonBalances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public monetaryPolicy;
    
    // Evento para rastrear cambios en la política monetaria
    event MonetaryPolicyUpdated(address oldPolicy, address newPolicy);

    constructor(address _policy) Ownable(msg.sender) {
        // Permitir inicialización con address(0), la política se establecerá después
        monetaryPolicy = _policy;
        _gonBalances[msg.sender] = TOTAL_GONS;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    modifier onlyPolicy() {
        require(msg.sender == monetaryPolicy, "not policy");
        require(monetaryPolicy != address(0), "policy not set");
        _;
    }
    
    /**
     * @notice Actualiza la dirección de la política monetaria
     * @param _newPolicy La nueva dirección de la política monetaria
     */
    function setMonetaryPolicy(address _newPolicy) external onlyOwner {
        require(_newPolicy != address(0), "Invalid policy address");
        address oldPolicy = monetaryPolicy;
        monetaryPolicy = _newPolicy;
        emit MonetaryPolicyUpdated(oldPolicy, _newPolicy);
    }

    /* -------- IERC20 -------- */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return _gonBalances[account] / _gonsPerFragment;
    }
    function transfer(address to, uint256 value) public override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 value) public override returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        require(current >= value, "ERC20: allowance");
        _allowances[from][msg.sender] = current - value;
        _transfer(from, to, value);
        return true;
    }

    /* -------- Rebase -------- */
    event LogRebase(uint256 indexed epoch, int256 supplyDelta);

    /// @notice Ajusta la oferta. supplyDelta puede ser positivo o negativo.
    function rebase(uint256 epoch, int256 supplyDelta) external onlyPolicy returns (uint256) {
        if (supplyDelta == 0) {
            emit LogRebase(epoch, supplyDelta);
            return _totalSupply;
        }

        if (supplyDelta < 0) {
            _totalSupply -= uint256(-supplyDelta);
        } else {
            _totalSupply += uint256(supplyDelta);
        }

        _gonsPerFragment = TOTAL_GONS / _totalSupply;
        emit LogRebase(epoch, supplyDelta);
        return _totalSupply;
    }

    /* -------- Internals -------- */
    function _transfer(address from, address to, uint256 value) internal {
        uint256 gonValue = value * _gonsPerFragment;
        _gonBalances[from] -= gonValue;
        _gonBalances[to]   += gonValue;
        emit Transfer(from, to, value);
    }
}