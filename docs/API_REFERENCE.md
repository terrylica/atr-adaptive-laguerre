# API Reference

Complete API documentation for the ATR-Adaptive Laguerre RSI library.

---

## Core Classes

### ATRAdaptiveLaguerreRSI

Main feature extractor class providing single-interval and multi-interval feature extraction.

**Module**: `atr_adaptive_laguerre.features`

**Import**:
```python
from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI
```

#### Constructor

```python
ATRAdaptiveLaguerreRSI(config: ATRAdaptiveLaguerreRSIConfig)
```

**Parameters**:
- `config` (ATRAdaptiveLaguerreRSIConfig): Configuration object defining extraction parameters

**Example**:
```python
config = ATRAdaptiveLaguerreRSIConfig(atr_period=32, smoothing_period=5)
feature = ATRAdaptiveLaguerreRSI(config)
```

#### Methods

##### fit_transform

```python
fit_transform(df: pd.DataFrame) -> pd.Series
```

Extract base ATR-Adaptive Laguerre RSI values (single column).

**Parameters**:
- `df` (pd.DataFrame): OHLCV dataframe with columns `['open', 'high', 'low', 'close', 'volume']`

**Returns**:
- `pd.Series`: RSI values in range [0.0, 1.0]

**Guarantees**:
- Non-anticipative: RSI[t] uses only data[0:t-1]
- Stateless: Each call creates fresh state

**Example**:
```python
rsi = feature.fit_transform(df)
# Output: Series with index matching df, values in [0.0, 1.0]
```

##### fit_transform_features

```python
fit_transform_features(df: pd.DataFrame) -> pd.DataFrame
```

Extract expanded feature set (31 single-interval or 133 multi-interval features).

**Parameters**:
- `df` (pd.DataFrame): OHLCV dataframe with columns `['open', 'high', 'low', 'close', 'volume']`

**Returns**:
- `pd.DataFrame`: Feature matrix
  - Single-interval (no multipliers): 31 features
  - Multi-interval (with multipliers): 133 features (31×3 + 40 interactions)

**Feature Categories** (single-interval):
1. Base indicator: `rsi`
2. Regime classification (7): `regime`, `regime_bullish`, `regime_neutral`, `regime_bearish`, etc.
3. Threshold distances (5): `dist_level_up`, `dist_level_down`, `abs_dist_level_up`, etc.
4. Level crossings (4): `cross_level_up`, `cross_level_down`, etc.
5. Temporal features (3): `bars_since_level_up_cross`, etc.
6. Rate of change (3): `rsi_change_1`, `rsi_velocity`, `rsi_acceleration`
7. Rolling statistics (4): `rsi_percentile_20`, `rsi_zscore_20`, `rsi_volatility_20`, `rsi_range_20`

**Multi-interval suffixes**:
- `_base`: Base interval (input data timeframe)
- `_mult1`: First multiplier interval (e.g., 3× base)
- `_mult2`: Second multiplier interval (e.g., 12× base)

**Cross-interval features** (40 total):
- Regime alignment: `all_intervals_bullish`, `all_intervals_bearish`, `regime_unanimity`, etc.
- Divergence metrics: `divergence_strength`, `divergence_base_mult1`, etc.
- Momentum consistency: `momentum_consistency`, `momentum_alignment`, etc.

**Example**:
```python
# Single-interval (31 features)
config = ATRAdaptiveLaguerreRSIConfig(atr_period=32, smoothing_period=5)
feature = ATRAdaptiveLaguerreRSI(config)
features = feature.fit_transform_features(df)
# Output: DataFrame with 31 columns

# Multi-interval (133 features)
config = ATRAdaptiveLaguerreRSIConfig(
    atr_period=32,
    smoothing_period=5,
    multiplier_1=3,    # 3× base interval
    multiplier_2=12,   # 12× base interval
)
feature = ATRAdaptiveLaguerreRSI(config)
features = feature.fit_transform_features(df)
# Output: DataFrame with 133 columns (31×3 + 40 interactions)
```

##### validate_non_anticipative

```python
validate_non_anticipative(
    df: pd.DataFrame,
    n_shuffles: int = 100,
    rtol: float = 1e-9,
    atol: float = 1e-12
) -> bool
```

Validate non-anticipative guarantee via progressive subset testing.

**Parameters**:
- `df` (pd.DataFrame): OHLCV dataframe to validate
- `n_shuffles` (int, default=100): Number of random subset tests
- `rtol` (float, default=1e-9): Relative tolerance for float comparison
- `atol` (float, default=1e-12): Absolute tolerance for float comparison

**Returns**:
- `bool`: True if non-anticipative guarantee holds, False otherwise

**Validation Logic**:
Computes features on progressively longer subsets and verifies that past features remain identical when future data is added.

**Example**:
```python
is_valid = feature.validate_non_anticipative(df, n_shuffles=100)
if is_valid:
    print("✓ Non-anticipative guarantee validated")
else:
    print("✗ Non-anticipative guarantee violated")
```

#### Properties

##### lookahead_bars_required

```python
@property
lookahead_bars_required() -> int
```

Minimum bars required for complete window filtering in multi-interval mode.

**Returns**:
- `int`: Number of lookahead bars needed (0 for single-interval, max(multiplier_1, multiplier_2) for multi-interval)

**Example**:
```python
config = ATRAdaptiveLaguerreRSIConfig(multiplier_1=3, multiplier_2=12)
feature = ATRAdaptiveLaguerreRSI(config)
print(feature.lookahead_bars_required)  # Output: 12
```

---

### ATRAdaptiveLaguerreRSIConfig

Configuration dataclass for ATR-Adaptive Laguerre RSI extraction.

**Module**: `atr_adaptive_laguerre.features`

**Import**:
```python
from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSIConfig
```

#### Fields

```python
@dataclass
class ATRAdaptiveLaguerreRSIConfig:
    atr_period: int = 32
    smoothing_period: int = 5
    level_up: float = 0.85
    level_down: float = 0.15
    multiplier_1: int | None = None
    multiplier_2: int | None = None
```

**Parameters**:
- `atr_period` (int, default=32): Period for ATR calculation and min/max tracking
- `smoothing_period` (int, default=5): Period for EMA smoothing of adaptive coefficient
- `level_up` (float, default=0.85): Upper threshold for regime classification (range: 0.0-1.0)
- `level_down` (float, default=0.15): Lower threshold for regime classification (range: 0.0-1.0)
- `multiplier_1` (int | None, default=None): First interval multiplier (e.g., 3 for 3× base)
- `multiplier_2` (int | None, default=None): Second interval multiplier (e.g., 12 for 12× base)

**Multi-Interval Behavior**:
- If both `multiplier_1` and `multiplier_2` are `None`: Single-interval mode (31 features)
- If both are set: Multi-interval mode (133 features)
- Setting only one multiplier is not supported

**Example**:
```python
# Single-interval configuration
config = ATRAdaptiveLaguerreRSIConfig(
    atr_period=32,
    smoothing_period=5,
    level_up=0.85,
    level_down=0.15,
)

# Multi-interval configuration
config = ATRAdaptiveLaguerreRSIConfig(
    atr_period=32,
    smoothing_period=5,
    level_up=0.85,
    level_down=0.15,
    multiplier_1=3,    # 3× base (e.g., 5min → 15min)
    multiplier_2=12,   # 12× base (e.g., 5min → 60min)
)
```

---

## Feature Expansion Classes

### FeatureExpander

Single-interval feature expansion (1 RSI column → 31 features).

**Module**: `atr_adaptive_laguerre.features`

**Import**:
```python
from atr_adaptive_laguerre import FeatureExpander
```

#### Methods

##### expand

```python
@staticmethod
expand(rsi: pd.Series, level_up: float = 0.85, level_down: float = 0.15) -> pd.DataFrame
```

Expand single RSI series to 31 derived features.

**Parameters**:
- `rsi` (pd.Series): RSI values in range [0.0, 1.0]
- `level_up` (float, default=0.85): Upper threshold
- `level_down` (float, default=0.15): Lower threshold

**Returns**:
- `pd.DataFrame`: 31-column feature matrix

**Example**:
```python
rsi = feature.fit_transform(df)
expanded = FeatureExpander.expand(rsi, level_up=0.85, level_down=0.15)
# Output: 31 columns including regime, crossings, temporal, tail risk, etc.
```

---

### MultiIntervalProcessor

Multi-interval orchestration (3 intervals → 133 features).

**Module**: `atr_adaptive_laguerre.features`

**Import**:
```python
from atr_adaptive_laguerre import MultiIntervalProcessor
```

#### Methods

##### process

```python
@staticmethod
process(
    df: pd.DataFrame,
    config: ATRAdaptiveLaguerreRSIConfig,
    base_rsi_calculator: Callable[[pd.DataFrame], pd.Series]
) -> pd.DataFrame
```

Process multi-interval feature extraction.

**Parameters**:
- `df` (pd.DataFrame): Base interval OHLCV data
- `config` (ATRAdaptiveLaguerreRSIConfig): Configuration with multipliers set
- `base_rsi_calculator` (Callable): Function to compute base RSI from OHLCV

**Returns**:
- `pd.DataFrame`: 133-column feature matrix (31×3 + 40 interactions)

**Internal Logic**:
1. Resample to multiplier intervals
2. Compute RSI for each interval
3. Expand each RSI to 31 features
4. Compute 40 cross-interval interactions
5. Concatenate all features

**Example**:
```python
def calculate_base_rsi(df: pd.DataFrame) -> pd.Series:
    config = ATRAdaptiveLaguerreRSIConfig(atr_period=32, smoothing_period=5)
    feature = ATRAdaptiveLaguerreRSI(config)
    return feature.fit_transform(df)

features = MultiIntervalProcessor.process(df, config, calculate_base_rsi)
# Output: 133 columns (31×3 + 40 interactions)
```

---

### CrossIntervalFeatures

Cross-interval interaction feature computation.

**Module**: `atr_adaptive_laguerre.features`

**Import**:
```python
from atr_adaptive_laguerre import CrossIntervalFeatures
```

#### Methods

##### compute

```python
@staticmethod
compute(base_features: pd.DataFrame, mult1_features: pd.DataFrame, mult2_features: pd.DataFrame) -> pd.DataFrame
```

Compute 40 cross-interval interaction features.

**Parameters**:
- `base_features` (pd.DataFrame): Base interval features (31 columns)
- `mult1_features` (pd.DataFrame): First multiplier interval features (31 columns)
- `mult2_features` (pd.DataFrame): Second multiplier interval features (31 columns)

**Returns**:
- `pd.DataFrame`: 40 cross-interval interaction features

**Feature Categories**:
1. **Regime alignment** (13): `all_intervals_bullish`, `all_intervals_bearish`, `regime_unanimity`, etc.
2. **Divergence metrics** (9): `divergence_strength`, `divergence_base_mult1`, etc.
3. **Momentum consistency** (6): `momentum_consistency`, `momentum_alignment`, etc.
4. **Extreme level analysis** (6): `extreme_level_count`, `extreme_level_base_mult1`, etc.
5. **Velocity metrics** (6): `velocity_alignment`, `max_velocity_interval`, etc.

**Example**:
```python
interactions = CrossIntervalFeatures.compute(base_features, mult1_features, mult2_features)
# Output: 40 columns
```

---

## Validation Functions

### calculate_information_coefficient

```python
calculate_information_coefficient(
    feature_series: pd.Series,
    prices: pd.Series,
    forward_periods: int = 5
) -> dict
```

Calculate Information Coefficient (IC) for predictive power assessment.

**Module**: `atr_adaptive_laguerre.validation`

**Import**:
```python
from atr_adaptive_laguerre import calculate_information_coefficient
```

**Parameters**:
- `feature_series` (pd.Series): Feature values (e.g., RSI)
- `prices` (pd.Series): Price series (typically close prices)
- `forward_periods` (int, default=5): Number of periods ahead for forward returns

**Returns**:
- `dict`: Result dictionary with keys:
  - `ic` (float): Spearman correlation between feature[t] and forward_return[t+k]
  - `n_valid` (int): Number of valid samples used
  - `forward_periods` (int): Forward period used

**Interpretation**:
- `|IC| > 0.03`: Strong predictive power
- `|IC| ∈ [0.01, 0.03]`: Weak predictive signal
- `|IC| < 0.01`: No predictive power

**Example**:
```python
rsi = feature.fit_transform(df)
prices = df['close']

ic_result = calculate_information_coefficient(rsi, prices, forward_periods=5)
print(f"IC: {ic_result['ic']:.4f}")
print(f"Valid samples: {ic_result['n_valid']}")

if abs(ic_result['ic']) > 0.03:
    print("✓ Feature has predictive power")
```

---

### validate_information_coefficient

```python
validate_information_coefficient(
    feature_series: pd.Series,
    prices: pd.Series,
    forward_periods: int = 5,
    min_ic: float = 0.03
) -> bool
```

Validate that feature achieves minimum Information Coefficient threshold.

**Module**: `atr_adaptive_laguerre.validation`

**Import**:
```python
from atr_adaptive_laguerre import validate_information_coefficient
```

**Parameters**:
- `feature_series` (pd.Series): Feature values
- `prices` (pd.Series): Price series
- `forward_periods` (int, default=5): Forward return period
- `min_ic` (float, default=0.03): Minimum IC threshold

**Returns**:
- `bool`: True if `|IC| >= min_ic`, False otherwise

**Example**:
```python
is_predictive = validate_information_coefficient(rsi, prices, forward_periods=5, min_ic=0.03)
if is_predictive:
    print("✓ Feature meets IC threshold")
```

---

### validate_non_anticipative

```python
validate_non_anticipative(
    feature_extractor: ATRAdaptiveLaguerreRSI,
    df: pd.DataFrame,
    n_shuffles: int = 100,
    rtol: float = 1e-9,
    atol: float = 1e-12
) -> bool
```

Validate non-anticipative guarantee via progressive subset testing.

**Module**: `atr_adaptive_laguerre.validation`

**Import**:
```python
from atr_adaptive_laguerre import validate_non_anticipative
```

**Parameters**:
- `feature_extractor` (ATRAdaptiveLaguerreRSI): Feature extractor instance
- `df` (pd.DataFrame): OHLCV dataframe
- `n_shuffles` (int, default=100): Number of random subset tests
- `rtol` (float, default=1e-9): Relative tolerance
- `atol` (float, default=1e-12): Absolute tolerance

**Returns**:
- `bool`: True if non-anticipative guarantee holds

**Example**:
```python
config = ATRAdaptiveLaguerreRSIConfig(atr_period=32, smoothing_period=5)
feature = ATRAdaptiveLaguerreRSI(config)

is_valid = validate_non_anticipative(feature, df, n_shuffles=100)
if is_valid:
    print("✓ Non-anticipative guarantee validated")
```

---

### validate_ood_robustness

```python
validate_ood_robustness(
    feature_extractor: ATRAdaptiveLaguerreRSI,
    df: pd.DataFrame,
    n_permutations: int = 100,
    max_std_ratio: float = 1.5
) -> bool
```

Validate out-of-distribution robustness via permutation testing.

**Module**: `atr_adaptive_laguerre.validation`

**Import**:
```python
from atr_adaptive_laguerre import validate_ood_robustness
```

**Parameters**:
- `feature_extractor` (ATRAdaptiveLaguerreRSI): Feature extractor instance
- `df` (pd.DataFrame): OHLCV dataframe
- `n_permutations` (int, default=100): Number of permutations to test
- `max_std_ratio` (float, default=1.5): Maximum allowed std(permuted) / std(original)

**Returns**:
- `bool`: True if feature distribution remains stable under permutations

**Example**:
```python
is_robust = validate_ood_robustness(feature, df, n_permutations=100)
if is_robust:
    print("✓ Feature is robust to distribution shifts")
```

---

## Data Adapters

### BinanceAdapter

Binance OHLCV data fetching adapter.

**Module**: `atr_adaptive_laguerre.data`

**Import**:
```python
from atr_adaptive_laguerre.data import BinanceAdapter
```

#### Constructor

```python
BinanceAdapter(base_url: str = "https://api.binance.com")
```

**Parameters**:
- `base_url` (str, default="https://api.binance.com"): Binance API base URL

#### Methods

##### fetch

```python
fetch(
    symbol: str,
    interval: str,
    start_date: str,
    end_date: str
) -> pd.DataFrame
```

Fetch OHLCV data from Binance.

**Parameters**:
- `symbol` (str): Trading pair symbol (e.g., "BTCUSDT")
- `interval` (str): Kline interval (e.g., "1m", "5m", "1h", "1d")
- `start_date` (str): Start date in "YYYY-MM-DD" format
- `end_date` (str): End date in "YYYY-MM-DD" format

**Returns**:
- `pd.DataFrame`: OHLCV dataframe with columns `['date', 'open', 'high', 'low', 'close', 'volume']`

**Example**:
```python
adapter = BinanceAdapter()
df = adapter.fetch("BTCUSDT", "1h", "2024-01-01", "2024-06-30")
# Output: DataFrame with OHLCV columns
```

---

### GaplessCryptoDataAdapter

Parquet-based data loading adapter for gapless-crypto-data format.

**Module**: `atr_adaptive_laguerre.data`

**Import**:
```python
from atr_adaptive_laguerre.data import GaplessCryptoDataAdapter
```

#### Constructor

```python
GaplessCryptoDataAdapter(base_path: str)
```

**Parameters**:
- `base_path` (str): Path to gapless-crypto-data root directory

#### Methods

##### load

```python
load(
    exchange: str,
    symbol: str,
    interval: str,
    start_date: str,
    end_date: str
) -> pd.DataFrame
```

Load OHLCV data from Parquet files.

**Parameters**:
- `exchange` (str): Exchange name (e.g., "binance")
- `symbol` (str): Trading pair (e.g., "BTCUSDT")
- `interval` (str): Timeframe (e.g., "1m", "5m", "1h")
- `start_date` (str): Start date "YYYY-MM-DD"
- `end_date` (str): End date "YYYY-MM-DD"

**Returns**:
- `pd.DataFrame`: OHLCV dataframe

**Example**:
```python
adapter = GaplessCryptoDataAdapter("/path/to/gapless-crypto-data")
df = adapter.load("binance", "BTCUSDT", "1h", "2024-01-01", "2024-06-30")
```

---

## Type Hints

This package includes type hints and distributes a `py.typed` marker (PEP 561). Type checkers like `mypy` and `pyright` will automatically discover type information.

**Example mypy usage**:
```bash
mypy your_script.py
```

---

## Version Information

```python
import atr_adaptive_laguerre

print(atr_adaptive_laguerre.__version__)  # e.g., "0.1.0"
print(atr_adaptive_laguerre.__all__)      # List of public exports
```

---

## Complete Import Reference

```python
# Main classes
from atr_adaptive_laguerre import (
    ATRAdaptiveLaguerreRSI,
    ATRAdaptiveLaguerreRSIConfig,
)

# Feature expansion
from atr_adaptive_laguerre import (
    FeatureExpander,
    MultiIntervalProcessor,
    CrossIntervalFeatures,
)

# Validation functions
from atr_adaptive_laguerre import (
    calculate_information_coefficient,
    validate_information_coefficient,
    validate_non_anticipative,
    validate_ood_robustness,
)

# Data adapters
from atr_adaptive_laguerre.data import (
    BinanceAdapter,
    GaplessCryptoDataAdapter,
)
```

---

## Notes

### Stateless Design

All feature extraction methods are **stateless** - each `fit_transform()` call creates fresh state. This is optimal for backtesting but requires refitting for each window in production inference.

**Backtesting (recommended)**:
```python
for train_df, test_df in walk_forward_splits:
    feature = ATRAdaptiveLaguerreRSI(config)
    train_features = feature.fit_transform_features(train_df)
    test_features = feature.fit_transform_features(test_df)
```

**Production inference** (requires refitting):
```python
# New bar arrives
df = append_new_bar(df, new_bar)
rsi = feature.fit_transform(df)  # Refits entire window
```

Future releases may add stateful incremental API for production use.

### Multi-Interval Lookahead

Multi-interval mode requires complete window filtering. Use the `lookahead_bars_required` property to determine minimum bars needed:

```python
config = ATRAdaptiveLaguerreRSIConfig(multiplier_1=3, multiplier_2=12)
feature = ATRAdaptiveLaguerreRSI(config)

print(feature.lookahead_bars_required)  # Output: 12

# Ensure df has enough bars
assert len(df) > feature.lookahead_bars_required
```

### Python Version Compatibility

- **Minimum**: Python 3.10
- **Tested**: Python 3.10, 3.11, 3.12, 3.13
- **Syntax**: PEP 604 union types (`int | None`)

---

For implementation details, see [Algorithm Documentation](algorithm.md).
For validation methodology, see [Validation Documentation](validation.md).
For downstream usage, see [Seq2Seq Integration Guide](seq2seq_integration.md).
