# Basalt Vault Backtest Results

## Overview

**Strategy**: Delta-neutral yield vault on Arbitrum. Deposits USDC into GMX V2 GM BTC/USDC market token, borrows WBTC on Dolomite to hedge BTC exposure, loops to ~2x leverage. Earns GM trading fees minus borrow cost with near-zero directional risk.

**Data**: 2 years of hourly on-chain data (Apr 19, 2024 -- Apr 19, 2026), 17,565 data points, 27 on-chain values per hour (Chainlink prices, GMX DataStore, Dolomite indices). Minute-resolution data also available (525,600 points for 1-year subset).

**Simulation parameters**: $10,000 initial deposit, 1% entry cost (slippage + gas on x2 loop), 0.5% slippage per rebalance swap, $0.80 gas per rebalance, Dolomite on-chain borrow index for interest accrual.

---

## 1. Headline Numbers (Website / Production Config)

Source: `web/src/lib/chartData.json` and `landingContent.ts`

| Metric | Value |
|--------|-------|
| Backtest APY | **19.7%** |
| Max drawdown | **-5.7%** |
| $10K becomes | **$14,316** |
| Rebalances (2 years) | **2** |
| Delta | ~0 |
| Target LTV | 50% (configurable 48-52%) |
| Rebalance metric | Dollar Delta, 17-20% threshold |

### vs Benchmarks (2-year, $10K initial)

| Strategy | Final NAV | Return |
|----------|-----------|--------|
| **Basalt Vault** | **$14,314** | **+43.1%** |
| GM HODL (no hedge) | $14,207 | +42.1% |
| 50/50 BTC/USDC | $12,925 | +29.3% |
| BTC HODL | $11,643 | +16.4% |

Basalt outperforms all benchmarks with lower drawdown (-5.7% vs -7.6% for unhedged GM).

---

## 2. GM Token Decomposition

Source: `xeyax/basalt-backtesting` -- `BACKTESTING_README.md`, `calc.ipynb`

### GM vs Alternatives by Year

| Scenario | Year 1 (bull) | Year 2 (bear) |
|----------|---------------|---------------|
| HODL 100% BTC | +31.2% | -15.4% |
| HODL 50/50 BTC/USDC | +15.6% | -7.7% |
| Uniswap V2 LP (no fees) | +14.6% | -8.0% |
| **GM BTC/USDC** | **+33.7%** | **+3.8%** |

GM outperforms in both bull and bear markets because trader fee income dominates directional loss.

### Theoretical Basalt Returns (unhedged fees * leverage - borrow cost)

| Period | Fee Yield | x2 Leveraged | Borrow Cost | Net |
|--------|-----------|--------------|-------------|-----|
| Year 1 | +19.4% | +38.8% | -4.9% | **+33.8%** |
| Year 2 | +11.9% | +23.7% | -3.5% | **+20.2%** |

---

## 3. Impermanent Loss Analysis

Source: `xeyax/basalt-backtesting` -- `calc.ipynb`, `worst_il.parquet`

### Worst-Case IL vs Fee Coverage

| Holding Period | Worst IL | Fees Earned | Net (Fees + IL) | Covered? |
|----------------|----------|-------------|-----------------|----------|
| 1 day | -0.76% | +1.40% | +0.64% | Yes |
| 1 week | -1.41% | +0.55% | -0.86% | No |
| 1 month | -2.39% | +1.17% | -1.22% | No |
| 3 months | -5.41% | +5.30% | -0.11% | Borderline |
| 1 year | -9.37% | +20.80% | +11.43% | Yes |

**Historical max IL drawdown**: -2.73% (worst entry: 2025-01-20, recovered in 43 days).

---

## 4. Core Backtest: LTV Threshold Sweep

Source: `xeyax/basalt-backtesting` -- `backtest_results.json`

All results: $10K deposit, 2 years, LTV-based rebalance metric.

| LTV Threshold | APY | Max DD | Calmar | Rebalances |
|---------------|-----|--------|--------|------------|
| HODL (no rebal) | 22.9% | -7.6% | 3.03 | 0 |
| 1% | 12.7% | -5.7% | 2.21 | 218 |
| 2% | 14.5% | -5.3% | 2.75 | 62 |
| 3% | 15.2% | -5.4% | 2.83 | 29 |
| 4% | 16.3% | -5.5% | 2.96 | 15 |
| 5% | 16.4% | -5.2% | 3.18 | 9 |
| 6% | 17.3% | -5.9% | 2.92 | 6 |
| 7% | 20.8% | -6.2% | 3.39 | 24 |
| **8%** | **19.7%** | **-5.3%** | **3.73** | **3** |
| 9% | 18.9% | -5.3% | 3.60 | 2 |
| 10% | 18.0% | -5.4% | 3.34 | 2 |
| 12% | 15.8% | -7.6% | 2.09 | 2 |
| 13%+ | 22.9% | -7.6% | 3.03 | 0 |

**Optimal zone**: LTV threshold 5-8%, giving APY 16-20% with max DD -5.2% to -6.2% and 3-9 rebalances over 2 years.

---

## 5. Dollar Delta Metric Results

Source: `xeyax/basalt-backtesting` -- `backtest_results.json`

| DD Threshold | APY | Max DD | Calmar | Rebalances |
|--------------|-----|--------|--------|------------|
| 5% | 13.1% | -5.2% | 2.51 | 50 |
| 10% | 16.9% | -5.2% | 3.26 | 8 |
| 15% | 18.8% | -5.7% | 3.30 | 3 |
| **17%** | **20.5%** | **-5.5%** | **3.70** | **2** |
| **20%** | **20.5%** | **-5.5%** | **3.73** | **2** |
| 25%+ | 22.9% | -7.6% | 3.03 | 0 |

**Best risk-adjusted**: Dollar Delta 17-20% threshold. Calmar 3.70-3.73, only 2 rebalances in 2 years.

---

## 6. Best Configurations by LTV Target (Advanced Sweep)

Source: `xeyax/basalt-backtesting` -- `BACKTESTING_README.md`, `gm_formula.ipynb`

| Target LTV | Threshold | APY | Max DD | APY/DD |
|------------|-----------|-----|--------|--------|
| 49% | 200bp | ~14% | -4% | 3.5 |
| 50% | 700bp | ~18% | -4% | 4.5 |
| 52% | 700bp | ~19% | -4% | 4.8 |
| 54% | 1200bp | ~18% | -3% | 5.3 |

**Sweet spot**: LTV 50-53%, threshold 500-800bp. APY 15-20%, Max DD -4% to -6%, rebalances 6-30/year, costs < $100/year on $10K.

---

## 7. Walk-Forward Validation (Year 1 In-Sample, Year 2 Out-of-Sample)

Source: `xeyax/basalt-backtesting` -- `HYPOTHESIS_REGIME_HYBRID.md`

| Strategy | Y1 APY | Y1 DD | Y1 Calmar | Y2 APY | Y2 DD | Y2 Calmar | Decay |
|----------|--------|-------|-----------|--------|-------|-----------|-------|
| HODL | 29.8% | -7.6% | 3.94 | 22.5% | -5.9% | 3.83 | -7.3% |
| DD 17% | 25.9% | -5.6% | 4.67 | 21.5% | -5.4% | 3.94 | -4.5% |
| DD 20% | 25.4% | -5.3% | 4.76 | 22.0% | -5.5% | 4.00 | -3.4% |
| LTV 7% | -- | -- | -- | -- | -- | -- | -- |

**DD 20% shows best stability** (-3.4% decay) with strong absolute performance in both periods.

### 3-Fold Temporal Cross-Validation

| Strategy | Fold 1 | Fold 2 | Fold 3 | Std Dev |
|----------|--------|--------|--------|---------|
| HODL | 27.0% | 30.2% | 21.8% | 3.4% |
| DD 17% | 28.9% | 28.9% | 14.1% | 7.0% |
| DD 20% | 29.0% | 28.8% | 14.1% | 7.0% |

HODL has lowest APY variance (3.4%) across folds but highest drawdown. DD 17-20% trades slightly more variance for meaningful DD protection.

---

## 8. GM Price Prediction Model

Source: `xeyax/basalt-backtesting` -- `BACKTESTING_README.md`, `gm_formula.ipynb`

```
gm_return = 0.48 * btc_return + 3.11 * borrow_fee_change + 0.001%/hr
R-squared = 0.97
```

97% of GM price movement explained by BTC price + borrowing fees. Rolling 60-day window: mean residual 1.0%, max 4.2%.

### BTC Exposure Composition (Coefficient of Variation)

| Component | Y1 CV | Y2 CV | % of GM Price |
|-----------|-------|-------|---------------|
| longPoolAmount / supply | 7.2% | 12.3% | ~51% |
| oiTokensLong / supply | 67.2% | 120.2% | ~6-13% |
| oiTokensShort / supply | 52.7% | 54.2% | ~12-17% |
| impactPool / supply | 100.8% | 62.6% | ~2-3% |

Pool BTC amount is stable (~7% CV); trader OI and impact pool are highly variable but represent small fractions of GM value.

---

## 9. Regime-Switching Analysis

Source: `xeyax/basalt-backtesting` -- `HYPOTHESIS_REGIME_HYBRID.md`, `backtest_regime_results.json`

### Regime Distribution (2 years)

| Regime | Hours | % |
|--------|-------|---|
| Sideways | 7,463 | 42.6% |
| Bear volatile | 3,102 | 17.7% |
| Bull calm | 2,844 | 16.2% |
| Bull volatile | 2,330 | 13.3% |
| Bear calm | 1,617 | 9.2% |

### Regime-Switching Strategies vs Static Baselines

| Strategy | APY | Max DD | Calmar | Rebalances |
|----------|-----|--------|--------|------------|
| **DD 20% (static)** | **20.5%** | **-5.5%** | **3.73** | **2** |
| DD 17% (static) | 20.5% | -5.6% | 3.70 | 2 |
| DD-triggered 3% | 18.4% | -5.7% | 3.23 | 10 |
| Vol-switch | 15.2% | -5.6% | 2.70 | 45 |
| 5-regime HMM | 15.6% | -5.7% | 2.75 | 35 |
| 3-regime simple | 14.2% | -5.9% | 2.42 | 37 |
| Momentum-switch | 13.4% | -11.6% | 1.15 | 14 |
| Combined vol+mom | 12.6% | -13.7% | 0.92 | 23 |

**Verdict**: All regime-switching strategies underperform static DD 17-20%. The delta-neutral structure makes the vault inherently regime-resistant. Transaction costs from frequent switching destroy value.

---

## 10. Volatility Metrics Analysis

Source: `xeyax/basalt-backtesting` -- `HYPOTHESIS_VOLATILITY_METRICS.md`, `volatility_metrics_analysis.json`

### Top Drawdown Predictors (ranked by composite score)

| Rank | Metric | Corr(DD_7d) | Quintile Q5/Q1 | Cohen's d (worst 5%) |
|------|--------|-------------|----------------|----------------------|
| 1 | **Impact Pool %** | -0.252 | 3.33x | 0.491 |
| 2 | **BTC/WBTC Spread Vol** | -0.178 | 2.06x | 0.618 |
| 3 | **Pool Ratio Drift** | -0.095 | 1.67x | 0.252 |
| 4 | GM/BTC Vol Ratio | +0.078 | 0.64x | -- |
| 5 | Borrow Rate | -0.063 | 1.18x | -- |
| 6 | 24h Realized Vol | -0.080 | 1.34x | 0.224 |
| 7 | Hedge Drift Speed | -0.050 | 1.46x | -- |

**Key finding**: Impact pool % is the single strongest predictor of drawdown events (3.33x quintile ratio). When the impact pool is elevated, the GM price becomes less efficient and the hedge degrades faster.

### Dolomite Borrow Rate Statistics

| Stat | Value |
|------|-------|
| Mean | 4.1% annualized |
| Median | 3.8% |
| P5 - P95 range | 0.7% -- 6.7% |

---

## 11. Approaches That Failed

Source: `xeyax/basalt-backtesting` -- `BACKTESTING_README.md`, `HYPOTHESIS_REGIME_HYBRID.md`

| Approach | Problem | Result |
|----------|---------|--------|
| **Pool-only hedge (PH1)** | Under-hedges by ~11% (pool = 51% of exposure, actual = 62.5%) | DD -6% to -8% |
| **ML-predicted beta target** | Beta ~0.44 vs real ~0.50-0.62, too conservative | Worse than simple LTV |
| **Kalman filter trigger** | Too sensitive, generates 1000+ rebalances | Slippage destroys returns |
| **Frequent rebalancing (< 300bp)** | Transaction costs eat profits | APY drops 5-10% |
| **5-regime HMM switching** | 1029 switches in 2 years, worst decay (-10.9%) | Overfit, underperforms |
| **Momentum-based switching** | Large drawdown events in regime transitions | DD -11.6%, Calmar 1.15 |
| **Composite vol+momentum** | Worst of both worlds | DD -13.7%, Calmar 0.92 |

**Core lesson**: Less is more. The delta-neutral vault earns from GM fees (regime-independent). Rebalancing adds cost and marginal risk reduction. Optimal strategy rebalances only 2 times in 2 years.

---

## 12. IL-vs-Slippage Dynamic Threshold

Source: `xeyax/basalt-backtesting` -- `HYPOTHESIS_IL_THRESHOLD.md`

### Breakeven Threshold Distribution (17,524 hours)

| Statistic | Value |
|-----------|-------|
| Valid hours (finite breakeven) | 5,212 / 17,524 (29.7%) |
| Mean | 9.07% |
| Median | 4.42% |
| P5 | 0.99% |
| P25 | 2.21% |
| P75 | 9.95% |
| P95 | 35.46% |

In 70.3% of hours, the volatility is too low to justify any rebalance (slippage always dominates IL). The optimal threshold is dynamic: tight during high-vol crashes, wide during calm markets. However, the simple static DD 17-20% approximates this well enough in practice.

---

## 13. Local Backtester (MPLM)

Source: `/home/user/projects/mplm/backtester/`

A separate general-purpose backtester for looping DeFi strategies, using DeFi Llama historical APY data.

**Architecture**: CLI tool that fetches daily supply APY from DeFi Llama, applies constant borrow rate and leverage, computes daily P&L with gas and slippage deductions.

**Differs from xeyax/basalt-backtesting**: Uses daily DeFi Llama APY aggregates (not raw on-chain hourly data). Simpler model -- no position-level GM decomposition, no hedge ratio tracking. Useful for quick screening across many strategies; the xeyax repo provides the authoritative high-fidelity backtest for Basalt specifically.

---

## 14. Audit Notes

Source: `xeyax/basalt-backtesting` -- `AUDIT.md`

| Finding | Severity | Impact |
|---------|----------|--------|
| **APY uses post-entry NAV, not $10K** | MEDIUM | Overstates APY by ~2.8pp (reports 22.9% instead of true 22.8% for HODL) |
| `lent_impact` missing from `wbtc_per_gm_full` | LOW | Only affects unusable Hedge_Full metric |
| Debt set to hedge=1.0, not from loop arithmetic | INFO | Initial LTV ~51.5% instead of 50%. Modeling choice. |
| `max_dd == worst_entry_dd` for all configs | INFO | Mathematically correct for this dataset; no information loss |
| GM price formula vs Dolomite oracle | INFO | ~0.55% systematic gap. Simulation uses oracle value, not computed. |

---

## 15. Key Parameters

| Parameter | Value |
|-----------|-------|
| Deposit token | USDC (native on Arbitrum) |
| Yield source | GM BTC/USDC (GMX V2 trading fees + funding) |
| Hedge instrument | WBTC debt on Dolomite |
| Target LTV | 50% |
| Safe cap | 70% (NFT owner can rebalance directly above this) |
| Liquidation threshold | ~83.8% (Dolomite) |
| Performance fee | 20% above high-water mark |
| Slippage per rebalance | 0.5% of swap amount |
| Gas + execution fee | $0.80 |
| Entry cost | ~1% of deposit (slippage + gas on x2 loop) |
| Dolomite WBTC borrow rate | ~3.5-5% annually (historical range) |
