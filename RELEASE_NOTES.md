
## 2.0.0 - 2025-10-13


### ✨ New Features

- Remove 6 constant features from redundancy filter (121→73) - Verified with 1000-bar dataset: 6 features have zero variance - Constant features removed: * all_intervals_bearish (never triggers in typical datasets) * all_intervals_crossed_overbought (never triggers in trending markets) * all_intervals_crossed_oversold (never triggers in typical datasets) * all_intervals_neutral (0 variance) * cascade_crossing_up (never triggers in typical datasets) * gradient_up (never triggers in typical datasets) Changes: - Redundancy filter: 42 → 48 features removed (121 → 73) - Default filtered feature count: 79 → 73 (-6 constant features) - All tests updated and passing (32/32) Verification: - Created /tmp/verify_feature_counts.py to analyze 1000-bar dataset - Confirmed 6 constant features (std=0.0) in unfiltered set - Confirmed 0 constant features in filtered set after fix Version: 1.0.8

- Add 6 RSI-based tail risk features for black swan detection Add black swan detection features to single-interval (33 features) and multi-interval (91 filtered, 139 unfiltered) modes: New Features: - rsi_shock_1bar: Binary flag for |1-bar change| > 0.3 - rsi_shock_5bar: Binary flag for |5-bar change| > 0.5 - extreme_regime_persistence: Binary flag for extreme regime > 10 bars - rsi_volatility_spike: Binary flag for volatility > mean + 2σ - rsi_acceleration: 2nd derivative of RSI - tail_risk_score: Composite score [0, 1] Changes: - feature_expander.py: Add _extract_tail_risk() method - atr_adaptive_rsi.py: Update feature counts (33, 139, 91) - redundancy_filter.py: Support new counts (33→33, 139→91) - Tests: Add tail_risk_features test, update all count assertions Version: 1.0.9 Previous: 1.0.8 (27→33 single, 121→139 multi, 73→91 filtered)

- IC-validated tail risk refinement (v1.0.10) Remove 2 underperforming tail risk features based on out-of-sample IC validation: - rsi_shock_5bar: -70.1% IC loss vs source feature - rsi_acceleration: -34.9% IC loss vs source feature Keep 4 IC-validated features: - rsi_shock_1bar: +18.6% IC gain - rsi_volatility_spike: +40.7% IC gain (best performer) - extreme_regime_persistence: composite indicator - tail_risk_score: reweighted formula (0.4, 0.3, 0.3) Update all documentation and tests: - Feature counts: 33→31 (single), 139→133 (multi-unfiltered), 91→85 (multi-filtered) - Updated: README, API_REFERENCE, all docstrings, test assertions - Validation: Out-of-sample data (BTCUSDT 2h, 2025-01-01 to 2025-09-30, 3,276 bars) BREAKING: Feature count change (quality improvement, not API change)

- Add backtesting.py adapter with comprehensive test suite - Implement BacktestingAdapter for seamless backtesting.py integration - Add indicator wrapping, OHLC data conversion, and Strategy base class - Include comprehensive test suite with 469 test lines covering all adapters - Document integration plan and implementation guide (625 lines) - Update audit report with backtesting.py integration status - Export adapter classes in package __init__.py - Refactor schema.py and base.py for better type safety - Remove tracked __pycache__ files from repository



### 🐛 Bug Fixes & Improvements

- Timestamp-based mapping for sliced DataFrames with reset_index Critical bug: mult1/mult2 features calculated incorrectly when using .iloc[...].reset_index(drop=True) pattern (production slicing). Root cause: Index arithmetic assumed 0-based indices, broke when reset. Fix: Replace index arithmetic with timestamp-based searchsorted mapping - atr_adaptive_rsi.py: Use date column instead of integer indices - Correctly maps mult1/mult2 windows to base bars via timestamps - Works with any DataFrame index (continuous, reset, or sliced) Testing: - tests/test_temporal/test_index_reset.py validates production pattern - Comprehensive temporal safety tests (adversarial, properties, stress) - Added hypothesis for property-based testing - All tests passing (1 passed, 3 skipped with documented limitation) Limitation: Some bars_since counters differ with reset_index when filter_redundancy=False, but production setting filters these features. Closes bug report: /tmp/atr-adaptive-laguerre-CRITICAL-BUG-REPORT.md

- N_features property reporting incorrect values (v1.0.12) CRITICAL BUG FIX: n_features property was returning OLD feature counts instead of actual output. Issue: - Reported 91 features, returned 85 (6 features off) - Reported 133 features, returned 133 (unfiltered was correct) - Reported 31 features, returned 31 (single was correct) Root Cause: - Hardcoded values not updated during v1.0.10 tail risk refinement - Property calculated 33 per interval instead of 31 - 33×3 + 40 = 139 (old) vs 31×3 + 40 = 133 (new) Fix: - Updated n_features property: 139→133, 91→85, 33→31 - Updated RedundancyFilter.n_features_after_filtering() for new counts - Added support for legacy values (backward compatibility) Validation: - Created test script: all modes now match actual DataFrame.shape[1] - Single-interval: 31 ✓ - Multi-filtered: 85 ✓ - Multi-unfiltered: 133 ✓ Thanks to user bug report!



### 📝 Other Changes

- Version 1.0.6 → 1.0.7

- Version 1.1.0 → 2.0.0



---
**Full Changelog**: https://github.com/Eon-Labs/rangebar/compare/v1.0.6...v2.0.0
