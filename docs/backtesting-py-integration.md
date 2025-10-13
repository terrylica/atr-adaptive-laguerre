# backtesting.py Framework Integration

**Version**: 1.1.0
**Status**: Production
**Compatibility**: backtesting.py >= 0.3.3

## Overview

atr-adaptive-laguerre package integrates with backtesting.py framework as custom indicator. Provides access to ATR-Adaptive Laguerre RSI and 31 extended features for strategy development.

## Installation

```bash
uv add atr-adaptive-laguerre backtesting
```

## SLO Guarantees

### Availability
- Functions callable when backtesting.py installed: 100%
- Import graceful failure with clear error message

### Correctness
- Column mapping bidirectional accuracy: 100%
- Non-anticipative property maintained: 100%
- Output value range [0.0, 1.0]: 100%
- Output length matches input length: 100%

### Observability
- Clear error messages for missing columns (lists missing columns)
- Clear error messages for invalid data types
- Clear error messages for invalid feature names (lists available features)

## API Reference

### atr_laguerre_indicator

Primary RSI indicator for backtesting.py Strategy.I() integration.

```python
def atr_laguerre_indicator(
    data: Any,
    atr_period: int = 14,
    smoothing_period: int = 5,
    adaptive_offset: float = 0.75,
    level_up: float = 0.85,
    level_down: float = 0.15,
) -> np.ndarray
```

**Parameters**:
- `data`: backtesting.py data object or pd.DataFrame (Title case columns required)
- `atr_period`: ATR lookback period (default: 14)
- `smoothing_period`: Price smoothing period (default: 5)
- `adaptive_offset`: Adaptive period offset coefficient (default: 0.75)
- `level_up`: Upper threshold (default: 0.85)
- `level_down`: Lower threshold (default: 0.15)

**Returns**: np.ndarray of RSI values [0.0, 1.0]

**Raises**:
- `TypeError`: Invalid data object type
- `ValueError`: Missing required columns

### atr_laguerre_features

Extract single feature from 31-feature expansion.

```python
def atr_laguerre_features(
    data: Any,
    feature_name: str = "rsi",
    atr_period: int = 14,
    smoothing_period: int = 5,
    adaptive_offset: float = 0.75,
    level_up: float = 0.85,
    level_down: float = 0.15,
) -> np.ndarray
```

**Parameters**: Same as `atr_laguerre_indicator` plus:
- `feature_name`: Feature to extract (default: 'rsi')

**Returns**: np.ndarray of feature values

**Raises**:
- `TypeError`: Invalid data object type
- `ValueError`: Missing columns or invalid feature_name

### make_atr_laguerre_indicator

Factory function for parameterized indicators.

```python
def make_atr_laguerre_indicator(
    atr_period: int = 14,
    smoothing_period: int = 5,
    adaptive_offset: float = 0.75,
    level_up: float = 0.85,
    level_down: float = 0.15,
) -> Callable[[Any], np.ndarray]
```

**Parameters**: Same as `atr_laguerre_indicator`

**Returns**: Callable function for Strategy.I()

## Usage Examples

### Basic Mean Reversion Strategy

```python
from backtesting import Backtest, Strategy
from atr_adaptive_laguerre import atr_laguerre_indicator
import pandas as pd

# Load OHLCV data (Title case columns required)
df = pd.read_csv('data.csv', index_col='Date', parse_dates=True)

class MeanReversionStrategy(Strategy):
    atr_period = 14
    oversold = 0.15
    overbought = 0.85

    def init(self):
        self.rsi = self.I(
            atr_laguerre_indicator,
            self.data,
            self.atr_period
        )

    def next(self):
        if self.rsi[-1] < self.oversold:
            if not self.position:
                self.buy()
        elif self.rsi[-1] > self.overbought:
            if self.position:
                self.position.close()

bt = Backtest(df, MeanReversionStrategy, cash=10000, commission=.002)
stats = bt.run()
print(stats)
bt.plot()
```

### Multi-Feature Strategy

```python
from atr_adaptive_laguerre import atr_laguerre_features

class MultiFeatureStrategy(Strategy):
    def init(self):
        self.rsi = self.I(
            atr_laguerre_features,
            self.data,
            feature_name='rsi'
        )
        self.regime = self.I(
            atr_laguerre_features,
            self.data,
            feature_name='regime'
        )
        self.volatility = self.I(
            atr_laguerre_features,
            self.data,
            feature_name='rsi_volatility_20'
        )
        self.tail_risk = self.I(
            atr_laguerre_features,
            self.data,
            feature_name='tail_risk_score'
        )

    def next(self):
        # Trade based on multiple features
        if self.regime[-1] == 0 and self.tail_risk[-1] > 0.5:
            # Bearish regime + high tail risk = avoid
            if self.position:
                self.position.close()
        elif self.rsi[-1] < 0.15 and self.volatility[-1] < 0.05:
            # Oversold + low volatility = buy
            if not self.position:
                self.buy()
```

### Dual-Timeframe Strategy

```python
from atr_adaptive_laguerre import make_atr_laguerre_indicator

fast_rsi = make_atr_laguerre_indicator(atr_period=10, smoothing_period=3)
slow_rsi = make_atr_laguerre_indicator(atr_period=20, smoothing_period=7)

class DualTimeframeStrategy(Strategy):
    def init(self):
        self.fast = self.I(fast_rsi, self.data)
        self.slow = self.I(slow_rsi, self.data)

    def next(self):
        # Buy when fast crosses above slow (both oversold)
        if (self.fast[-1] > self.slow[-1] and
            self.fast[-2] <= self.slow[-2] and
            self.slow[-1] < 0.3):
            if not self.position:
                self.buy()

        # Sell when fast crosses below slow (both overbought)
        elif (self.fast[-1] < self.slow[-1] and
              self.fast[-2] >= self.slow[-2] and
              self.slow[-1] > 0.7):
            if self.position:
                self.position.close()
```

### Parameter Optimization

```python
class OptimizableStrategy(Strategy):
    atr_period = 14
    oversold = 0.15
    overbought = 0.85

    def init(self):
        self.rsi = self.I(
            atr_laguerre_indicator,
            self.data,
            self.atr_period
        )

    def next(self):
        if self.rsi[-1] < self.oversold:
            if not self.position:
                self.buy()
        elif self.rsi[-1] > self.overbought:
            if self.position:
                self.position.close()

# Optimize parameters
stats = bt.optimize(
    atr_period=range(10, 30, 2),
    oversold=[0.1, 0.15, 0.2],
    overbought=[0.8, 0.85, 0.9],
    maximize='Sharpe Ratio',
    constraint=lambda p: p.oversold < 0.5 < p.overbought
)

print(f"Best Sharpe: {stats['Sharpe Ratio']:.2f}")
print(f"Best parameters: atr_period={stats._strategy.atr_period}, "
      f"oversold={stats._strategy.oversold}, "
      f"overbought={stats._strategy.overbought}")
```

## Available Features

Access via `atr_laguerre_features(data, feature_name='...')`:

| Category | Features |
|----------|----------|
| **Base** | `rsi` |
| **Regimes** | `regime`, `regime_bearish`, `regime_neutral`, `regime_bullish`, `regime_changed`, `bars_in_regime`, `regime_strength` |
| **Thresholds** | `dist_overbought`, `dist_oversold`, `dist_midline`, `abs_dist_overbought`, `abs_dist_oversold` |
| **Crossings** | `cross_above_oversold`, `cross_below_overbought`, `cross_above_midline`, `cross_below_midline` |
| **Temporal** | `bars_since_oversold`, `bars_since_overbought`, `bars_since_extreme` |
| **Rate of Change** | `rsi_change_1`, `rsi_change_5`, `rsi_velocity` |
| **Statistics** | `rsi_percentile_20`, `rsi_zscore_20`, `rsi_volatility_20`, `rsi_range_20` |
| **Tail Risk** | `rsi_shock_1bar`, `extreme_regime_persistence`, `rsi_volatility_spike`, `tail_risk_score` |

## Data Requirements

### Column Names (Title Case Required)

backtesting.py requires Title case columns:

```python
# ✅ CORRECT
df = pd.DataFrame({
    'Open': [...],
    'High': [...],
    'Low': [...],
    'Close': [...],
    'Volume': [...]
})

# ❌ INCORRECT
df = pd.DataFrame({
    'open': [...],   # lowercase not supported by backtesting.py
    'high': [...],
    'low': [...],
    'close': [...],
    'volume': [...]
})
```

### Minimum Data

- Single-interval mode: ~30 bars minimum for warmup
- Recommendation: 50-100 bars for stable statistics
- Values before warmup forward-filled from first valid value

### DatetimeIndex

Recommended but not required:

```python
df.index = pd.date_range('2024-01-01', periods=len(df), freq='1h')
```

## Non-Anticipative Guarantee

All indicators maintain non-anticipative property:
- Indicator value at bar `i` only uses data from bars `0` to `i-1`
- No lookahead bias
- Validated via progressive subset testing

## Comparison: Backtesting vs ML Use Cases

| Use Case | Function | Output | Features |
|----------|----------|--------|----------|
| **Backtesting** | `atr_laguerre_indicator()` | Single RSI series | Simple indicator |
| **Backtesting** | `atr_laguerre_features()` | Single feature series | Access to 31 features |
| **ML Training** | `indicator.fit_transform_features()` | DataFrame with 31-133 columns | Full feature matrix |

Backtesting adapter provides simplified access to same computation engine used for ML feature generation.

## Error Handling

All errors propagate without fallbacks:

```python
# Missing columns
>>> atr_laguerre_indicator(df_missing_columns)
ValueError: Data missing required columns: ['close', 'volume'].
Available columns: ['Open', 'High', 'Low'].
Expected Title case: ['Open', 'High', 'Low', 'Close', 'Volume']

# Invalid data type
>>> atr_laguerre_indicator([1, 2, 3])
TypeError: data must be backtesting.py data object or pd.DataFrame, got list

# Invalid feature name
>>> atr_laguerre_features(df, feature_name='invalid')
ValueError: Feature 'invalid' not found.
Available features (31): ['abs_dist_overbought', 'abs_dist_oversold', ...]
```

## Performance Characteristics

- Vectorized computation: full dataset processed once in `init()`
- No incremental updates during `next()` (values pre-computed and indexed)
- Sequential Laguerre filter state updates (cannot be fully vectorized)
- Warmup period: ~20-30 bars depending on parameters

## Version History

- **1.1.0** (2025-10-10): Initial backtesting.py integration
  - Added `backtesting_adapter.py` module
  - Three public functions: `atr_laguerre_indicator`, `atr_laguerre_features`, `make_atr_laguerre_indicator`
  - SLO guarantees defined and validated
  - Comprehensive test coverage

## References

- backtesting.py documentation: https://kernc.github.io/backtesting.py/
- Package repository: https://github.com/terryli710/atr-adaptive-laguerre
- API specifications: `/docs/backtesting-py-integration-plan.md`
