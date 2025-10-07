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
- ✅ **Multi-interval**: Supports 1s-1d timeframes with 121-feature extraction
- ✅ **Flexible datetime**: Works with DatetimeIndex, 'date' column, or custom column names
- ✅ **Validated**: Information coefficient > 0.03 on k-step-ahead returns

## Installation

```bash
uv add atr-adaptive-laguerre
```

## Quick Start

### Basic Usage (Single RSI Value)

```python
from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig
import pandas as pd

# Create indicator with flexible datetime support
config = ATRAdaptiveLaguerreRSIConfig(
    atr_period=14,
    smoothing_period=5,
    date_column='date'  # Or use DatetimeIndex
)
indicator = ATRAdaptiveLaguerreRSI(config)

# Batch processing
rsi_series = indicator.fit_transform(df)  # Returns pd.Series

# Incremental updates (O(1) streaming)
new_row = {'open': 100, 'high': 101, 'low': 99, 'close': 100.5, 'volume': 1000}
new_rsi = indicator.update(new_row)  # Returns float
```

### Multi-Interval Feature Extraction (121 Features)

```python
# Extract features across 3 intervals (5m, 15m, 1h example)
config = ATRAdaptiveLaguerreRSIConfig(
    atr_period=14,
    smoothing_period=5,
    multiplier_1=3,   # 15m features (5m × 3)
    multiplier_2=12   # 1h features (5m × 12)
)
feature = ATRAdaptiveLaguerreRSI(config)

# Returns DataFrame with 121 columns:
# - 27 base interval features (*_base)
# - 27 mult1 interval features (*_mult1)
# - 27 mult2 interval features (*_mult2)
# - 40 cross-interval interactions
features_df = feature.fit_transform_features(df)

# Check minimum required data
print(f"Need {feature.min_lookback_base_interval} bars for multi-interval")
```

## Documentation

- [API Reference](https://github.com/Eon-Labs/atr-adaptive-laguerre/blob/main/docs/API_REFERENCE.md) - Complete API documentation
- [Examples](https://github.com/Eon-Labs/atr-adaptive-laguerre/tree/main/examples) - Runnable usage examples
- [Changelog](https://github.com/Eon-Labs/atr-adaptive-laguerre/blob/main/CHANGELOG.md) - Release notes and version history

## License

MIT License - Eon Labs Ltd.
