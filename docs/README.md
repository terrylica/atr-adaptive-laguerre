# ATR-Adaptive Laguerre RSI

Non-anticipative volatility-adaptive momentum indicator for sequence-to-sequence forecasting.

## Overview

This library implements the ATR-Adaptive Laguerre RSI indicator, designed for robust feature engineering in financial time series forecasting. The indicator combines:

- **True Range (TR)** - Volatility measurement including gaps
- **ATR with Min/Max Tracking** - Rolling volatility envelope
- **Adaptive Coefficient** - Volatility-normalized adaptation
- **Laguerre 4-Stage Cascade** - Low-lag smoothing filter
- **Laguerre RSI** - Momentum from filter stage differences

## Key Features

- ✅ **Non-anticipative**: Guaranteed no lookahead bias
- ✅ **O(1) Incremental**: Efficient streaming updates with `.update()` method
- ✅ **Multi-interval**: Supports 1s-1d timeframes with 79-feature extraction (121 without filtering)
- ✅ **Redundancy filtering**: Optional 121→79 feature reduction (|ρ| > 0.9 removed)
- ✅ **Flexible datetime**: Works with DatetimeIndex, 'date' column, or custom column names
- ✅ **Validated**: Information coefficient > 0.03 on k-step-ahead returns

## Installation

```bash
uv add atr-adaptive-laguerre
```

## Feature Modes: Choose Your Use Case

This package supports two operational modes with very different capabilities:

| Mode | Features | Lookback | Use Case |
|------|----------|----------|----------|
| **Multi-Interval** (Recommended) | **79** | 360 bars | Production ML pipelines - includes cross-timeframe analysis |
| **Single-Interval** | 27 | 30 bars | Minimal data requirements or single-timeframe analysis |

### ⚠️ Important: Multi-Interval Mode is Recommended

**If you're building ML features, you want multi-interval mode (79 features)**, which includes:
- Base interval features (16)
- First multiplier interval features (15)
- Second multiplier interval features (17)
- **Cross-interval analysis features (31)** ← Unique to multi-interval mode!

Cross-interval features detect multi-timeframe patterns like:
- Regime alignment across timeframes
- Divergence detection
- Momentum cascades
- Gradient analysis
- Statistical stability metrics

## Quick Start

### Multi-Interval Mode (Recommended - 79 Features)

```python
from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig

# RECOMMENDED: Use multi-interval mode for full feature set
config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
    multiplier_1=4,   # 4x base interval (e.g., 2h → 8h)
    multiplier_2=12   # 12x base interval (e.g., 2h → 24h)
)
indicator = ATRAdaptiveLaguerreRSI(config)

# Extract 79 features across 3 timeframes
features_df = indicator.fit_transform_features(df)

print(f"Features extracted: {indicator.n_features}")  # 79
print(f"Min data required: {indicator.min_lookback_base_interval} bars")  # 360
```

### Single-Interval Mode (Minimal Lookback - 27 Features)

Use this mode only if you have limited historical data or need single-timeframe analysis:

```python
from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig

# Single-interval mode (WARNING: only 27 features, missing cross-timeframe analysis)
config = ATRAdaptiveLaguerreRSIConfig(
    atr_period=14,
    smoothing_period=5,
    date_column='date'  # Or use DatetimeIndex
)
indicator = ATRAdaptiveLaguerreRSI(config)

# Get single RSI value
rsi_series = indicator.fit_transform(df)  # Returns pd.Series (single RSI column)

# Or get 27 single-interval features
features_df = indicator.fit_transform_features(df)  # Returns DataFrame with 27 columns

print(f"Features extracted: {indicator.n_features}")  # 27
print(f"Min data required: {indicator.min_lookback} bars")  # 30
```

### Advanced: Incremental Updates (O(1) Streaming)

Both modes support efficient incremental updates:

```python
# After initial fit_transform
new_row = {'open': 100, 'high': 101, 'low': 99, 'close': 100.5, 'volume': 1000}
new_rsi = indicator.update(new_row)  # Returns float (O(1) complexity)
```

### Disabling Redundancy Filtering (79 → 121 Features)

```python
# Disable redundancy filtering to get all 121 features
config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
    multiplier_1=4,
    multiplier_2=12,
    filter_redundancy=False  # Get all 121 features
)
feature = ATRAdaptiveLaguerreRSI(config)

# Returns DataFrame with 121 columns (all features, including 42 redundant ones)
features_df = feature.fit_transform_features(df)

# Verify feature count
print(f"Features: {feature.n_features}")  # 121 (79 by default)

# Redundancy filtering (enabled by default):
# - Data: 3 years of 2h OHLCV (BTCUSDT, ETHUSDT, SOLUSDT)
# - Threshold: |ρ| > 0.9 (perfect correlations and near-redundant features)
# - Removes: Base RSI values, redundant distance metrics, duplicate regime features
# - Retains: Rate-of-change, cross-interval, and temporal features
# - IC validation: +45.54% improvement (PASSED)
```

## Documentation

- [API Reference](https://github.com/Eon-Labs/atr-adaptive-laguerre/blob/main/docs/API_REFERENCE.md) - Complete API documentation
- [Examples](https://github.com/Eon-Labs/atr-adaptive-laguerre/tree/main/examples) - Runnable usage examples
- [Changelog](https://github.com/Eon-Labs/atr-adaptive-laguerre/blob/main/CHANGELOG.md) - Release notes and version history

## License

MIT License - Eon Labs Ltd.
