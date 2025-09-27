# 🔚 Position Closing Commands - Complete Guide

## 📋 Current Position Status
Based on your portfolio:
- **Position #2**: SHORT 0.225 VETH with 300 USDC margin
- **Current PnL**: Break-even (0.00 USDC)
- **Mark Price**: 2000 USDC per VETH

## 🎯 **Correct Position Closing Commands**

### **Method 1: Managed Closing (Recommended)** ✅ **BEST**
```bash
# Close 100% of Position #2 (complete closure)
bun run closePositionManaged.ts 2

# Close 50% of Position #2 (partial closure)
bun run closePositionManaged.ts 2 50

# Close 25% of Position #2 (small partial closure)
bun run closePositionManaged.ts 2 25

# Close 75% of Position #2 (large partial closure)
bun run closePositionManaged.ts 2 75
```

### **Method 2: Via Swap Mechanism** ✅ **ALTERNATIVE**
```bash
# Close Position #2 completely via swap
bun run closePositionViaSwap.ts 2
```

### **Method 3: Basic Close Position** ⚠️ **USE WITH CAUTION**
```bash
# Close Position #2 (basic method)
bun run closePosition.ts 2
```

## 📊 **Recommended Commands for Your Current Position**

### **For Position #2 (SHORT 0.225 VETH)**

#### **Complete Closure (Get all margin back)**
```bash
bun run closePositionManaged.ts 2
```
**Expected Result:**
- Position #2 will be completely closed
- ~300 USDC margin returned to free balance
- Total free balance: ~1,325 USDC

#### **Partial Closure (Keep some exposure)**
```bash
# Close 50% - Keep 0.1125 VETH SHORT exposure
bun run closePositionManaged.ts 2 50

# Close 75% - Keep 0.0563 VETH SHORT exposure  
bun run closePositionManaged.ts 2 75
```

## 🔍 **Command Format Explanation**

### **closePositionManaged.ts** (Recommended)
```bash
bun run closePositionManaged.ts <tokenId> [percentage]
```

**Parameters:**
- `<tokenId>`: Position ID (required) - For you: **2**
- `[percentage]`: Size to close (optional, default: 100)
  - `100` = Close entire position
  - `50` = Close half the position
  - `25` = Close quarter of the position

**Features:**
- ✅ Safe margin calculations
- ✅ Proper position size validation
- ✅ Comprehensive error handling
- ✅ Transaction confirmation waiting
- ✅ Balance verification before/after

### **closePositionViaSwap.ts** (Alternative)
```bash
bun run closePositionViaSwap.ts <tokenId>
```

**Parameters:**
- `<tokenId>`: Position ID (required) - For you: **2**

**Features:**
- ✅ Uses swap mechanism for closing
- ✅ May be better for larger positions
- ✅ Alternative routing method

## 🚀 **Step-by-Step Closing Process**

### **1. Check Position Before Closing**
```bash
bun run quickPortfolio.ts
```

### **2. Close Position (Choose one method)**
```bash
# Option A: Complete closure (recommended for break-even)
bun run closePositionManaged.ts 2

# Option B: Partial closure (if you want to keep some exposure)
bun run closePositionManaged.ts 2 50
```

### **3. Verify Closure Success**
```bash
bun run quickPortfolio.ts
```

## 💡 **Pro Tips for Your Position**

### **Since your position is at break-even (0.00 PnL):**

#### **Complete Closure - Best Option**
```bash
bun run closePositionManaged.ts 2
```
**Why:** No profit/loss, get full margin back, clean slate

#### **Partial Closure - If Bullish on ETH**
```bash
bun run closePositionManaged.ts 2 50
```
**Why:** Keep SHORT exposure if you think ETH will drop

## ⚠️ **Important Notes**

### **Before Closing:**
- Position #2 is currently **break-even** (good time to close)
- You'll get back your **300 USDC margin** on complete closure
- **No slippage impact** since you're at entry price

### **After Closing:**
- Free balance will increase by the margin amount
- Locked balance will decrease accordingly
- Position will be removed from portfolio

## 🎯 **Recommended Action for You**

**Based on your current break-even status:**

```bash
# RECOMMENDED: Close completely and take back your 300 USDC
bun run closePositionManaged.ts 2
```

This will:
- ✅ Close your SHORT position completely
- ✅ Return 300 USDC margin to your free balance  
- ✅ Clean up your portfolio
- ✅ Give you ~1,325 USDC total free balance

## 🔄 **Verification Commands**

**Before closing:**
```bash
bun run quickPortfolio.ts
# Should show: 1025 USDC free, 1490 USDC locked, Position #2 active
```

**After closing:**
```bash
bun run quickPortfolio.ts  
# Should show: ~1325 USDC free, ~1190 USDC locked, No Position #2
```

---

**Ready to close? Run:** `bun run closePositionManaged.ts 2` 🚀
