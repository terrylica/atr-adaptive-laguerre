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
- ✅ **O(1) Incremental**: Efficient online computation (talipp pattern)
- ✅ **Multi-interval**: Supports 1s-1d timeframes
- ✅ **Validated**: Information coefficient > 0.03 on k-step-ahead returns

## Installation

```bash
uv add atr-adaptive-laguerre
```

## Quick Start

```python
from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig
from atr_adaptive_laguerre.data import BinanceAdapter

# Fetch data
adapter = BinanceAdapter()
df = adapter.fetch("BTCUSDT", "1h", "2024-01-01", "2024-06-30")

# Create feature
config = ATRAdaptiveLaguerreRSIConfig(atr_period=32, smoothing_period=5)
feature = ATRAdaptiveLaguerreRSI(config)

# Transform (non-anticipative)
rsi_series = feature.fit_transform(df)
```

## Documentation

- [API Reference](https://github.com/Eon-Labs/atr-adaptive-laguerre/blob/main/docs/API_REFERENCE.md) - Complete API documentation
- [Examples](https://github.com/Eon-Labs/atr-adaptive-laguerre/tree/main/examples) - Runnable usage examples
- [Changelog](https://github.com/Eon-Labs/atr-adaptive-laguerre/blob/main/CHANGELOG.md) - Release notes and version history

## License

MIT License - Eon Labs Ltd.
