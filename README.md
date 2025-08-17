# LossProtection - Uniswap V4 Impermanent Loss Protection Hook

A sophisticated Uniswap V4 hook contract that provides impermanent loss protection and comprehensive liquidity event tracking for DeFi users.

##  Overview

LossProtection is a Uniswap V4 hook that automatically tracks user liquidity positions, calculates impermanent loss in real-time, and provides insurance mechanisms to protect users from significant losses when removing liquidity.

## ✨ Features

###  **Impermanent Loss Protection**
- **Real-time IL Calculation**: Automatically calculates impermanent loss during liquidity removal
- **Insurance Eligibility**: Determines if users qualify for insurance based on loss thresholds
- **Claim Management**: Tracks all insurance claims with detailed metadata

### 📊 **Comprehensive Event Tracking**
- **Liquidity Events**: Records all add/remove liquidity operations with timestamps
- **Price Tracking**: Stores token prices at the time of each liquidity event
- **Historical Analysis**: Maintains complete history of user interactions

### 🎛️ **Hook Integration**
- **Uniswap V4 Compatible**: Fully integrated with Uniswap V4's hook system
- **Permission Management**: Configurable hook permissions for different operations
- **Gas Efficient**: Optimized for minimal gas consumption

### 🛡️ **Insurance System**
- **Automatic Detection**: Identifies impermanent loss scenarios automatically
- **Insurance Calculation**: Computes exact insurance amounts needed
- **Multi-Claim Support**: Handles multiple insurance claims per user

## ️ Architecture

### **Core Components**

```solidity
contract LossProtection is BaseHook {
    // Event tracking
    mapping(address => LiquidityEvent[]) public userEvents;
    mapping(address => Claims[]) public claimEvents;
    
    // Hook permissions
    mapping(PoolId => uint256) public beforeSwapCount;
    mapping(PoolId => uint256) public afterSwapCount;
    mapping(PoolId => uint256) public beforeAddLiquidityCount;
    mapping(PoolId => uint256) public afterAddLiquidityCount;
    mapping(PoolId => uint256) public beforeRemoveLiquidityCount;
}
```

### **Data Structures**

#### **LiquidityEvent**
```solidity
struct LiquidityEvent {
    bool isAdd;           // true for addLiquidity, false for removeLiquidity
    uint256 amountA;      // Amount of Token A (in wei)
    uint256 amountB;      // Amount of Token B (in wei)
    uint256 priceA;       // Price of Token A at event time (scaled, 1e18)
    uint256 priceB;       // Price of Token B at event time (scaled, 1e18)
    uint256 timestamp;    // Timestamp of the event
}
```

#### **Claims**
```solidity
struct Claims {
    uint256 valueHold;    // Value of holding tokens
    uint256 valuePool;    // Value of pool tokens
    uint256 totalAddedA;  // Total amount of token A added
    uint256 totalAddedB;  // Total amount of token B added
    uint256 withdrawnA;   // Amount of token A withdrawn
    uint256 withdrawnB;   // Amount of token B withdrawn
    uint256 priceA;       // Price of token A at claim time
    uint256 priceB;       // Price of token B at claim time
    uint256 timestamp;    // Timestamp of the claim
}
```

## 🚀 Getting Started

### **Prerequisites**
- Foundry (latest version)
- Solidity ^0.8.26
- Uniswap V4 environment

### **Installation**

1. **Clone the repository**
```bash
git clone <repository-url>
cd loss-protection
```

2. **Install dependencies**
```bash
forge install
```

3. **Build the contract**
```bash
forge build
```

### **Local Development**

1. **Start Anvil**
```bash
anvil
```

2. **Deploy the contract**
```bash
forge script script/00_DeployHook.s.sol:DeployHookScript \
  --rpc-url http://localhost:8545 \
  --broadcast \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

### **Testing**

```bash
# Run all tests
forge test

# Run specific test with verbose output
forge test --match-contract LossProtectionTest -vv

# Run tests against local network
forge test --fork-url http://localhost:8545
```

##  API Reference

### **Core Functions**

#### **Liquidity Management**
```solidity
// Hook automatically tracks these operations
function _afterAddLiquidity(...) internal override
function _afterRemoveLiquidity(...) internal override
```

#### **Insurance Functions**
```solidity
// Get insurance for latest claim
function claimInsurance(address user) public view returns (uint256 insuranceAmount, bool hasLoss)

// Get insurance for specific claim
function getInsuranceForClaim(address user, uint256 claimIndex) public view returns (uint256 insuranceAmount, bool hasLoss)

// Get total insurance across all claims
function getTotalInsurance(address user) public view returns (uint256 totalInsurance, uint256 totalLosses)

// Check eligibility
function isEligibleForInsurance(address user) public view returns (bool eligible, uint256 totalInsurance)
```

#### **Data Access Functions**
```solidity
// Get claim count
function getClaimCount(address user) public view returns (uint256)

// Get specific claim
function getClaim(address user, uint256 index) public view returns (Claims memory)

// Get oracle prices
function getOraclePrice(address currency0, address currency1) public pure returns (uint256 priceA, uint256 priceB)
```

### **Events**

#### **ClaimCreated**
```solidity
event ClaimCreated(
    address indexed user,
    uint256 valueHold,
    uint256 valuePool,
    uint256 totalAddedA,
    uint256 totalAddedB,
    uint256 withdrawnA,
    uint256 withdrawnB,
    uint256 priceA,
    uint256 priceB,
    uint256 timestamp
);
```

#### **LiquidityEventRecorded**
```solidity
event LiquidityEventRecorded(
    address indexed user,
    bool isAdd,
    uint256 amountA,
    uint256 amountB,
    uint256 timestamp
);
```

##  Configuration

### **Hook Permissions**
```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize: false,
        afterInitialize: false,
        beforeAddLiquidity: true,
        afterAddLiquidity: true,
        beforeRemoveLiquidity: false,
        afterRemoveLiquidity: true,
        beforeSwap: true,
        afterSwap: true,
        // ... other permissions
    });
}
```

### **Price Oracle**
Currently uses hardcoded prices for development:
- **Token A**: 10e18 (10.0)
- **Token B**: 20e18 (20.0)

**Future Enhancement**: Integrate with Chainlink or other price oracles.

## 📊 Usage Examples

### **Basic Insurance Check**
```solidity
// Check if user has insurance to claim
(uint256 insurance, bool hasLoss) = lossProtection.claimInsurance(userAddress);

if (hasLoss) {
    console.log("Insurance amount:", insurance);
    // Process insurance claim
}
```

### **Historical Analysis**
```solidity
// Get total insurance across all claims
(uint256 totalInsurance, uint256 totalLosses) = lossProtection.getTotalInsurance(userAddress);

console.log("Total insurance needed:", totalInsurance);
console.log("Number of loss events:", totalLosses);
```

### **Claim Details**
```solidity
// Get details of a specific claim
Claims memory claim = lossProtection.getClaim(userAddress, 0);

console.log("Claim valueHold:", claim.valueHold);
console.log("Claim valuePool:", claim.valuePool);
console.log("Impermanent loss:", claim.valueHold - claim.valuePool);
```

## 🧪 Testing

### **Test Coverage**
- ✅ Liquidity addition tracking
- ✅ Liquidity removal tracking
- ✅ Impermanent loss calculation
- ✅ Insurance eligibility checks
- ✅ Claim management
- ✅ Event emission
- ✅ Price oracle integration

### **Running Tests**
```bash
# Run all tests
forge test

# Run with coverage
forge coverage

# Run specific test file
forge test --match-path test/LossProtection.t.sol
```

## 🚨 Security Considerations

### **Current Limitations**
- **Hardcoded Prices**: Oracle prices are currently hardcoded for development
- **No Access Control**: All functions are public (suitable for hook contracts)
- **No Pause Mechanism**: Contract cannot be paused in emergency

### **Production Recommendations**
- Integrate with decentralized price oracles
- Implement access control for admin functions
- Add emergency pause functionality
- Conduct comprehensive security audits

## 🔮 Roadmap

### **Phase 1: Core Functionality** ✅
- [x] Basic impermanent loss tracking
- [x] Insurance calculation
- [x] Event logging
- [x] Hook integration

### **Phase 2: Enhanced Features**
- [ ] Real-time price oracle integration
- [ ] Advanced loss analytics
- [ ] Multi-pool support
- [ ] Gas optimization

### **Phase 3: Production Ready**
- [ ] Security audits
- [ ] Access control implementation
- [ ] Emergency mechanisms
- [ ] Mainnet deployment

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

##  Acknowledgments

- **Uniswap V4 Team** for the innovative hook architecture
- **Foundry Team** for the excellent development framework
- **OpenZeppelin** for secure contract patterns

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/your-repo/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-repo/discussions)
- **Documentation**: [Wiki](https://github.com/your-repo/wiki)

---

**Built with ❤️ for the DeFi community**

*Protect your liquidity, maximize your gains! ️💰*
