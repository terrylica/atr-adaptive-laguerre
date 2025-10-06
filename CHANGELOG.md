# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2025-10-06

### Fixed
- Documentation links in PyPI README now use absolute GitHub URLs instead of broken relative paths
- Updated links point to API Reference, Examples, and Changelog on GitHub

---

## [0.1.0] - 2025-10-06

### Added

#### Core Features
- ATR-Adaptive Laguerre RSI indicator with non-anticipative guarantee
- Multi-interval feature extraction (27 single-interval, 121 multi-interval features)
- O(1) incremental computation following talipp pattern
- Support for 1-second to 1-day timeframes

#### Feature Extraction
- Single-interval extraction: 27 features (base RSI + 26 derived features)
- Multi-interval extraction: 121 features (3 intervals + 40 cross-interval interactions)
- Feature categories:
  - Base indicator (RSI)
  - Regime classification (7 features)
  - Threshold distances (5 features)
  - Level crossings (4 features)
  - Temporal features (3 features)
  - Rate of change (3 features)
  - Rolling statistics (4 features)

#### Validation Framework
- Information Coefficient (IC) calculation for predictive power validation
- Non-anticipative guarantee validation via progressive subset testing
- Walk-forward backtest validation with strict train/test separation
- Out-of-distribution robustness testing

#### API Exports
- `ATRAdaptiveLaguerreRSI` - Main feature extractor class
- `ATRAdaptiveLaguerreRSIConfig` - Configuration dataclass
- `FeatureExpander` - Single-interval feature expansion (27 features)
- `MultiIntervalProcessor` - Multi-interval orchestration
- `CrossIntervalFeatures` - Cross-interval interaction features
- `calculate_information_coefficient` - IC computation
- `validate_information_coefficient` - IC validation
- `validate_non_anticipative` - Non-anticipative guarantee validation
- `validate_ood_robustness` - Out-of-distribution robustness testing

#### Data Adapters
- `BinanceAdapter` - Binance OHLCV data fetching
- `GaplessCryptoDataAdapter` - Parquet-based data loading

#### Documentation
- Complete algorithm documentation (`docs/algorithm.md`)
- API reference documentation (`docs/api.md`)
- Validation methodology (`docs/validation.md`)
- Seq2seq integration guide (`docs/seq2seq_integration.md`)
- README with quick start guide

#### Examples
- `01_basic_single_interval.py` - 27-feature extraction with synthetic data
- `02_multi_interval_features.py` - 121-feature extraction with interval alignment
- `03_walk_forward_backtest.py` - Production backtest template with train/test separation
- `04_api_discovery.py` - API probing demonstration for third-party users

#### Testing
- Comprehensive test suite (21 tests)
- Walk-forward validation tests (9 tests)
- Non-anticipative guarantee verification
- Train/test separation validation
- Cross-interval feature integrity tests

#### Package Distribution
- Python 3.10+ compatibility
- Type hints distribution via `py.typed` marker (PEP 561)
- MIT license
- PyPI-ready package structure

### Changed
- Minimum Python version: 3.10 (previously 3.12)

### Fixed
- README.md: Corrected class name from `ATRConfig` to `ATRAdaptiveLaguerreRSIConfig`

---

## Release Notes

### Version 0.1.0 - Initial Release

This is the first public release of the ATR-Adaptive Laguerre RSI library, providing a production-ready feature extraction pipeline for financial time series forecasting.

**Key Highlights**:
- ✅ **Non-anticipative**: Guaranteed no lookahead bias via progressive subset validation
- ✅ **O(1) Incremental**: Efficient online computation suitable for real-time inference
- ✅ **Multi-interval**: Extract features across 1-3 timeframes with cross-interval interactions
- ✅ **Validated**: Information coefficient > 0.03 on k-step-ahead returns
- ✅ **Production-ready**: Stateless design ideal for walk-forward backtesting

**Ideal For**:
- Seq2seq model feature engineering (LSTM, Transformer inputs)
- Walk-forward backtesting with strict temporal separation
- Real-time inference with O(1) incremental updates
- Multi-timeframe momentum analysis

**Getting Started**:
```bash
uv add atr-adaptive-laguerre
```

```python
from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig

config = ATRAdaptiveLaguerreRSIConfig(atr_period=32, smoothing_period=5)
feature = ATRAdaptiveLaguerreRSI(config)
rsi_series = feature.fit_transform(df)  # Non-anticipative extraction
```

**Examples**:
All examples work standalone without repository access:
```bash
uv run --with atr-adaptive-laguerre python examples/01_basic_single_interval.py
uv run --with atr-adaptive-laguerre python examples/02_multi_interval_features.py
uv run --with atr-adaptive-laguerre python examples/03_walk_forward_backtest.py
uvx --from atr-adaptive-laguerre python -m examples.04_api_discovery
```

**Validation**:
- 21 unit tests passing
- 9 walk-forward validation tests passing
- Zero temporal leakage confirmed
- 100% compliance with train/test separation rules

**Known Limitations**:
- Stateless design requires refitting for each window (optimal for backtesting)
- Stateful API for production inference planned for future release
- Multi-interval resampling requires complete window filtering (lookahead_bars_required property)

---

[0.1.0]: https://github.com/eon-labs/atr-adaptive-laguerre/releases/tag/v0.1.0
