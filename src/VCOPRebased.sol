// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "v4-core/lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title VCOPRebased
 * @notice Implementación de una stablecoin algorítmica que utiliza mecanismo de rebase
 * para mantener su precio cercano a 1 COP (peso colombiano)
 * @dev Este token usa 6 decimales para mantener compatibilidad con USDC
 */
contract VCOPRebased is ERC20, Ownable {
    // Eventos
    event Rebase(uint256 epoch, uint256 totalSupply, uint256 rebaseFactor);
    event RebaseParametersUpdated(
        uint256 rebaseThresholdUp, 
        uint256 rebaseThresholdDown, 
        uint256 rebasePercentageUp, 
        uint256 rebasePercentageDown
    );

    // Parámetros de rebase - Ahora basados en la relación VCOP/COP
    // Los umbrales están en términos de la relación VCOP/COP donde 1:1 es el ideal (1e6)
    uint256 public rebaseThresholdUp = 105e4; // 1.05 COP por VCOP
    uint256 public rebaseThresholdDown = 95e4; // 0.95 COP por VCOP
    uint256 public rebasePercentageUp = 1e4; // 1% de expansión
    uint256 public rebasePercentageDown = 1e4; // 1% de contracción

    // Contador de rebases
    uint256 public epoch = 0;

    // Direcciones autorizadas para realizar rebases
    mapping(address => bool) public rebasers;

    // Multiplicador para tracking de balances
    uint256 private _gonsPerFragment;
    
    // Balances internos (gons)
    mapping(address => uint256) private _gonBalances;
    
    // Allowances para gastar tokens
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // Suministro total en gons
    uint256 private _totalSupply;
    uint256 private _gonsSupply;
    
    // Factor inicial de gons (extremadamente grande para evitar problemas de redondeo)
    uint256 private constant INITIAL_GONS_SUPPLY = 2**128; 

    /**
     * @dev Constructor que inicializa el token con el suministro inicial y su dueño
     * @param initialSupply El suministro inicial del token (en unidades con 6 decimales)
     */
    constructor(uint256 initialSupply) ERC20("VCOP Stablecoin", "VCOP") Ownable(msg.sender) {
        _gonsSupply = INITIAL_GONS_SUPPLY;
        _gonsPerFragment = _gonsSupply / initialSupply;
        _totalSupply = initialSupply;
        
        // Asignar el suministro inicial al creador
        _gonBalances[msg.sender] = _gonsSupply;
        rebasers[msg.sender] = true;
        
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    /**
     * @dev Sobrecarga la función decimals para devolver 6 en lugar de 18 (valor predeterminado de ERC20)
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @dev Modifica los parámetros de rebase
     */
    function updateRebaseParameters(
        uint256 _rebaseThresholdUp,
        uint256 _rebaseThresholdDown,
        uint256 _rebasePercentageUp,
        uint256 _rebasePercentageDown
    ) external onlyOwner {
        require(_rebaseThresholdUp > _rebaseThresholdDown, "Thresholds invalid");
        require(_rebasePercentageUp > 0 && _rebasePercentageDown > 0, "Percentages must be > 0");
        
        rebaseThresholdUp = _rebaseThresholdUp;
        rebaseThresholdDown = _rebaseThresholdDown;
        rebasePercentageUp = _rebasePercentageUp;
        rebasePercentageDown = _rebasePercentageDown;
        
        emit RebaseParametersUpdated(
            _rebaseThresholdUp,
            _rebaseThresholdDown,
            _rebasePercentageUp,
            _rebasePercentageDown
        );
    }

    /**
     * @dev Autoriza o revoca a una dirección para ejecutar rebases
     */
    function setRebaser(address rebaser, bool authorized) external onlyOwner {
        rebasers[rebaser] = authorized;
    }

    /**
     * @dev Ejecuta un rebase basado en el precio actual
     * @param vcopToCopRate La tasa actual VCOP/COP (en formato 6 decimales, ej: 1 COP = 1e6)
     * @return El nuevo suministro total después del rebase
     */
    function rebase(uint256 vcopToCopRate) external returns (uint256) {
        require(rebasers[msg.sender], "Not authorized to rebase");
        
        uint256 newTotalSupply = _totalSupply;
        
        if (vcopToCopRate >= rebaseThresholdUp) {
            // Expansión (rebase positivo) - VCOP vale más que 1 COP
            uint256 factor = rebasePercentageUp;
            uint256 supplyDelta = (_totalSupply * factor) / 1e6;
            newTotalSupply = _totalSupply + supplyDelta;
        } else if (vcopToCopRate <= rebaseThresholdDown) {
            // Contracción (rebase negativo) - VCOP vale menos que 1 COP
            uint256 factor = rebasePercentageDown;
            uint256 supplyDelta = (_totalSupply * factor) / 1e6;
            newTotalSupply = _totalSupply - supplyDelta;
        } else {
            // No rebase si el precio está dentro del rango aceptable
            return _totalSupply;
        }
        
        if (newTotalSupply != _totalSupply) {
            _gonsPerFragment = _gonsSupply / newTotalSupply;
            _totalSupply = newTotalSupply;
            
            epoch++;
            
            emit Rebase(epoch, newTotalSupply, _gonsPerFragment);
        }
        
        return _totalSupply;
    }

    /**
     * @dev Obtener el valor que un propietario ha permitido gastar a un spender
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev Sobrecarga de balanceOf para tener en cuenta el factor de rebase
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _gonBalances[account] / _gonsPerFragment;
    }

    /**
     * @dev Retorna el suministro total actual
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Transfiere tokens teniendo en cuenta el mecanismo de rebase
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(to != address(0), "Transfer to zero address");
        
        uint256 gonAmount = amount * _gonsPerFragment;
        _gonBalances[msg.sender] -= gonAmount;
        _gonBalances[to] += gonAmount;
        
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @dev Permite transferencias desde una dirección a otra, considerando el factor de rebase
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = msg.sender;
        uint256 currentAllowance = _allowances[from][spender];
        require(currentAllowance >= amount, "Transfer amount exceeds allowance");
        
        uint256 gonAmount = amount * _gonsPerFragment;
        _gonBalances[from] -= gonAmount;
        _gonBalances[to] += gonAmount;
        
        unchecked {
            _allowances[from][spender] = currentAllowance - amount;
        }
        
        emit Transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Aprueba gastos desde una dirección
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        require(spender != address(0), "Approve to zero address");
        
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        
        return true;
    }
} 