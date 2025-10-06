# Feature Extraction Implementation Plan

**Version:** 1.0.0
**Created:** 2025-10-06
**Status:** Active
**Scope:** MQL5 visual elements → 121 columnized features for seq2seq models
**Supersedes:** None (initial plan)

---

## Objectives

### Primary
Transform ATR-Adaptive Laguerre RSI from 1 column → 121 columns capturing:
1. Base indicator values (27 features × 3 intervals = 81)
2. Cross-interval interactions (40 features)

### Constraints
- Non-anticipative: All features[t] use only data from [0, t-1]
- Deterministic: Same input → same output
- Integer multiples: Higher intervals = base_interval × multiplier
- Forward-fill alignment: Higher interval features aligned to base via ffill

---

## Service Level Objectives (SLOs)

### Availability
- Feature extraction success rate: ≥99.9% (max 1 failure per 1000 calls)
- Input validation coverage: 100% (all invalid inputs raise explicit errors)

### Correctness
- Non-anticipative guarantee: 100% (all 121 features pass progressive subset test)
- Feature range validation: 100% (all features within documented bounds)
- Numerical stability: ≥99.99% (max 1 NaN per 10k bars after warmup)

### Observability
- Type hints: 100% coverage (mypy strict mode)
- Docstrings: 100% coverage (all public APIs documented)
- Error messages: Include feature name, timestamp, and failure context

### Maintainability
- Code reuse: ≥80% (leverage pandas/numpy built-ins)
- Function complexity: ≤50 lines per function (single responsibility)
- Test coverage: ≥95% (line coverage for feature_expander module)

---

## Architecture

### Component Hierarchy

```
ATRAdaptiveLaguerreRSI (orchestrator)
├─> fit_transform() → pd.Series (1 column, existing)
└─> fit_transform_features() → pd.DataFrame (121 columns, new)
    ├─> FeatureExpander._extract_single_interval() → 27 columns
    │   ├─> _extract_regimes() → 7 columns
    │   ├─> _extract_thresholds() → 5 columns
    │   ├─> _extract_crossings() → 4 columns
    │   ├─> _extract_temporal() → 3 columns
    │   ├─> _extract_roc() → 3 columns
    │   ├─> _extract_statistics() → 4 columns
    │   └─> Base RSI → 1 column
    ├─> MultiIntervalProcessor._resample_and_extract() → 81 columns
    │   ├─> _resample_ohlcv(multiplier_1) → OHLCV at mult1 interval
    │   ├─> _resample_ohlcv(multiplier_2) → OHLCV at mult2 interval
    │   ├─> fit_transform() on each interval
    │   └─> _align_to_base() → forward-fill to base resolution
    └─> CrossIntervalFeatures._extract_interactions() → 40 columns
        ├─> _regime_alignment() → 6 columns
        ├─> _regime_divergence() → 8 columns
        ├─> _momentum_patterns() → 6 columns
        ├─> _crossing_patterns() → 8 columns
        └─> _temporal_patterns() → 12 columns
```

### Data Flow

```
Input: OHLCV DataFrame (base interval, e.g., 5m)
  ↓
Step 1: Compute base RSI (existing fit_transform)
  ↓
Step 2: Extract 27 single-interval features from base RSI
  ↓
Step 3: If multipliers provided:
  ├─> Resample OHLCV to mult1 interval (e.g., 15m)
  ├─> Compute RSI + 27 features for mult1
  ├─> Forward-fill to base resolution
  ├─> Resample OHLCV to mult2 interval (e.g., 1h)
  ├─> Compute RSI + 27 features for mult2
  └─> Forward-fill to base resolution
  ↓
Step 4: Extract 40 cross-interval interaction features
  ↓
Output: DataFrame with 121 columns (or 27 if no multipliers)
```

---

## Feature Specification

### Category 1: Base Indicator (1 column)

| Column | Type | Range | Formula | Non-Anticipative |
|--------|------|-------|---------|------------------|
| `rsi` | float64 | [0, 1] | Laguerre RSI from 4-stage filter | ✅ Uses close[t], state[t-1] |

### Category 2: Regime Classification (7 columns)

| Column | Type | Range | Formula | Non-Anticipative |
|--------|------|-------|---------|------------------|
| `regime` | int64 | {0,1,2} | 0 if rsi<0.15, 2 if rsi>0.85, else 1 | ✅ Uses rsi[t] |
| `regime_bearish` | int64 | {0,1} | 1 if regime==0, else 0 | ✅ |
| `regime_neutral` | int64 | {0,1} | 1 if regime==1, else 0 | ✅ |
| `regime_bullish` | int64 | {0,1} | 1 if regime==2, else 0 | ✅ |
| `regime_changed` | int64 | {0,1} | 1 if regime[t] != regime[t-1], else 0 | ✅ Uses regime[t-1] |
| `bars_in_regime` | int64 | [0, ∞) | Count of consecutive bars in current regime | ✅ Cumulative from past |
| `regime_strength` | float64 | [0, 1] | max(rsi - 0.85, 0) + max(0.15 - rsi, 0) | ✅ Uses rsi[t] |

### Category 3: Threshold Distances (5 columns)

| Column | Type | Range | Formula | Non-Anticipative |
|--------|------|-------|---------|------------------|
| `dist_overbought` | float64 | (-∞, ∞) | rsi - 0.85 | ✅ |
| `dist_oversold` | float64 | (-∞, ∞) | rsi - 0.15 | ✅ |
| `dist_midline` | float64 | [-0.5, 0.5] | rsi - 0.5 | ✅ |
| `abs_dist_overbought` | float64 | [0, 1] | abs(rsi - 0.85) | ✅ |
| `abs_dist_oversold` | float64 | [0, 1] | abs(rsi - 0.15) | ✅ |

### Category 4: Threshold Crossings (4 columns)

| Column | Type | Range | Formula | Non-Anticipative |
|--------|------|-------|---------|------------------|
| `cross_above_oversold` | int64 | {0,1} | 1 if rsi[t-1]≤0.15 and rsi[t]>0.15 | ✅ Uses rsi[t-1] |
| `cross_below_overbought` | int64 | {0,1} | 1 if rsi[t-1]≥0.85 and rsi[t]<0.85 | ✅ Uses rsi[t-1] |
| `cross_above_midline` | int64 | {0,1} | 1 if rsi[t-1]≤0.5 and rsi[t]>0.5 | ✅ Uses rsi[t-1] |
| `cross_below_midline` | int64 | {0,1} | 1 if rsi[t-1]≥0.5 and rsi[t]<0.5 | ✅ Uses rsi[t-1] |

### Category 5: Temporal Persistence (3 columns)

| Column | Type | Range | Formula | Non-Anticipative |
|--------|------|-------|---------|------------------|
| `bars_since_oversold` | int64 | [0, ∞) | Count since last rsi<0.15 | ✅ Cumulative |
| `bars_since_overbought` | int64 | [0, ∞) | Count since last rsi>0.85 | ✅ Cumulative |
| `bars_since_extreme` | int64 | [0, ∞) | min(bars_since_oversold, bars_since_overbought) | ✅ |

### Category 6: Rate of Change (3 columns)

| Column | Type | Range | Formula | Non-Anticipative |
|--------|------|-------|---------|------------------|
| `rsi_change_1` | float64 | [-1, 1] | rsi[t] - rsi[t-1] | ✅ Uses rsi[t-1] |
| `rsi_change_5` | float64 | [-1, 1] | rsi[t] - rsi[t-5] | ✅ Uses rsi[t-5] |
| `rsi_velocity` | float64 | [-1, 1] | pd.Series.ewm(span=5).mean(rsi_change_1) | ✅ EMA uses past only |

### Category 7: Local Statistics (4 columns)

| Column | Type | Range | Formula | Non-Anticipative |
|--------|------|-------|---------|------------------|
| `rsi_percentile_20` | float64 | [0, 100] | rsi[t] percentile rank over rolling 20 bars | ✅ Rolling window |
| `rsi_zscore_20` | float64 | (-∞, ∞) | (rsi[t] - mean_20) / std_20 | ✅ Rolling mean/std |
| `rsi_volatility_20` | float64 | [0, ∞) | std(rsi) over rolling 20 bars | ✅ Rolling std |
| `rsi_range_20` | float64 | [0, 1] | max_20 - min_20 | ✅ Rolling max/min |

### Category 8: Multi-Interval (Replicate 1-7 for mult1, mult2)

Each of categories 1-7 repeated for:
- Base interval (suffix: `_base`)
- Multiplier 1 interval (suffix: `_mult1`)
- Multiplier 2 interval (suffix: `_mult2`)

**Total:** 27 × 3 = 81 columns

### Category 9: Cross-Interval Interactions (40 columns)

#### 9a: Regime Alignment (6 columns)

| Column | Type | Range | Formula |
|--------|------|-------|---------|
| `all_intervals_bullish` | int64 | {0,1} | regime_base==2 & regime_mult1==2 & regime_mult2==2 |
| `all_intervals_bearish` | int64 | {0,1} | regime_base==0 & regime_mult1==0 & regime_mult2==0 |
| `all_intervals_neutral` | int64 | {0,1} | regime_base==1 & regime_mult1==1 & regime_mult2==1 |
| `regime_agreement_count` | int64 | {0,1,2,3} | Sum of intervals with same regime |
| `regime_majority` | int64 | {0,1,2} | Mode of [regime_base, regime_mult1, regime_mult2] |
| `regime_unanimity` | int64 | {0,1} | 1 if all 3 regimes equal |

#### 9b: Regime Divergence (8 columns)

| Column | Type | Range | Formula |
|--------|------|-------|---------|
| `base_bull_higher_bear` | int64 | {0,1} | regime_base==2 & (regime_mult1==0 \| regime_mult2==0) |
| `base_bear_higher_bull` | int64 | {0,1} | regime_base==0 & (regime_mult1==2 \| regime_mult2==2) |
| `divergence_strength` | float64 | [0, 1] | max(rsi_base, rsi_mult1, rsi_mult2) - min(...) |
| `divergence_direction` | int64 | {-1,0,1} | sign(rsi_base - rsi_mult2) |
| `base_extreme_higher_neutral` | int64 | {0,1} | (regime_base∈{0,2}) & regime_mult2==1 |
| `base_neutral_higher_extreme` | int64 | {0,1} | regime_base==1 & (regime_mult2∈{0,2}) |
| `gradient_up` | int64 | {0,1} | rsi_base > rsi_mult1 > rsi_mult2 |
| `gradient_down` | int64 | {0,1} | rsi_base < rsi_mult1 < rsi_mult2 |

#### 9c: Momentum Patterns (6 columns)

| Column | Type | Range | Formula |
|--------|------|-------|---------|
| `rsi_spread_base_mult1` | float64 | [-1, 1] | rsi_base - rsi_mult1 |
| `rsi_spread_base_mult2` | float64 | [-1, 1] | rsi_base - rsi_mult2 |
| `rsi_spread_mult1_mult2` | float64 | [-1, 1] | rsi_mult1 - rsi_mult2 |
| `momentum_direction` | int64 | {-1,0,1} | sign(rsi_spread_base_mult2) |
| `momentum_magnitude` | float64 | [0, 1] | abs(rsi_spread_base_mult2) |
| `momentum_consistency` | int64 | {0,1} | sign(rsi_change_1_base)==sign(rsi_change_1_mult2) |

#### 9d: Crossing Patterns (8 columns)

| Column | Type | Range | Formula |
|--------|------|-------|---------|
| `any_interval_crossed_overbought` | int64 | {0,1} | cross_below_overbought_base \| _mult1 \| _mult2 |
| `all_intervals_crossed_overbought` | int64 | {0,1} | cross_below_overbought_base & _mult1 & _mult2 |
| `any_interval_crossed_oversold` | int64 | {0,1} | cross_above_oversold_base \| _mult1 \| _mult2 |
| `all_intervals_crossed_oversold` | int64 | {0,1} | cross_above_oversold_base & _mult1 & _mult2 |
| `base_crossed_while_higher_extreme` | int64 | {0,1} | cross_above_oversold_base & (regime_mult2∈{0,2}) |
| `cascade_crossing_up` | int64 | {0,1} | cross_above_oversold in sequence (mult2 → mult1 → base) |
| `cascade_crossing_down` | int64 | {0,1} | cross_below_overbought in sequence |
| `higher_crossed_first` | int64 | {0,1} | mult2 crossed before base (within 10 bars) |

#### 9e: Temporal Patterns (12 columns)

| Column | Type | Range | Formula |
|--------|------|-------|---------|
| `regime_persistence_ratio` | float64 | [0, ∞) | bars_in_regime_base / bars_in_regime_mult2 |
| `regime_change_cascade` | int64 | {0,1} | regime_changed_mult2 preceded regime_changed_base |
| `regime_stability_score` | float64 | [0, 1] | 1 - (regime_changed_base + _mult1 + _mult2) / 3 |
| `bars_since_alignment` | int64 | [0, ∞) | Bars since regime_unanimity==1 |
| `alignment_duration` | int64 | [0, ∞) | Consecutive bars with regime_unanimity==1 |
| `higher_leading_base` | int64 | {0,1} | regime_mult2 changed N bars before regime_base |
| `regime_transition_pattern` | int64 | {0-7} | 3-bit encoding of regime sequence |
| `mean_rsi_across_intervals` | float64 | [0, 1] | (rsi_base + rsi_mult1 + rsi_mult2) / 3 |
| `std_rsi_across_intervals` | float64 | [0, ∞) | std([rsi_base, rsi_mult1, rsi_mult2]) |
| `rsi_range_across_intervals` | float64 | [0, 1] | max(...) - min(...) |
| `rsi_skew_across_intervals` | float64 | (-∞, ∞) | (rsi_base - mean) / std |
| `interval_momentum_agreement` | int64 | {0,1,2,3} | Count of intervals with rsi_change_1 > 0 |

**Total Category 9:** 6 + 8 + 6 + 8 + 12 = 40 columns

**Grand Total:** 27 (base) + 54 (mult1+mult2) + 40 (interactions) = **121 columns**

---

## Implementation Tasks

### Task 1: FeatureExpander Class
**File:** `src/atr_adaptive_laguerre/features/feature_expander.py`
**Lines:** ~400
**Dependencies:** pandas, numpy

**Methods:**
- `__init__(level_up=0.85, level_down=0.15, stats_window=20, velocity_span=5)`
- `expand(rsi: pd.Series) → pd.DataFrame` (orchestrator)
- `_extract_regimes(rsi) → pd.DataFrame[7 cols]`
- `_extract_thresholds(rsi) → pd.DataFrame[5 cols]`
- `_extract_crossings(rsi) → pd.DataFrame[4 cols]`
- `_extract_temporal(rsi) → pd.DataFrame[3 cols]`
- `_extract_roc(rsi) → pd.DataFrame[3 cols]`
- `_extract_statistics(rsi) → pd.DataFrame[4 cols]`

**Error Handling:**
- Raise ValueError if rsi is not pd.Series
- Raise ValueError if rsi contains values outside [0, 1]
- Raise ValueError if stats_window > len(rsi)
- Propagate all pandas/numpy errors

**SLOs:**
- Correctness: All features within documented ranges
- Observability: Function-level logging for each category
- Maintainability: Each extraction function ≤50 lines

### Task 2: MultiIntervalProcessor Class
**File:** `src/atr_adaptive_laguerre/features/multi_interval.py`
**Lines:** ~250
**Dependencies:** pandas

**Methods:**
- `__init__(multiplier_1=3, multiplier_2=12)`
- `resample_and_extract(df: pd.DataFrame, feature_extractor) → pd.DataFrame[81 cols]`
- `_resample_ohlcv(df, multiplier) → pd.DataFrame`
- `_validate_multiplier(multiplier) → None`
- `_align_to_base(features_higher, base_index) → pd.DataFrame`

**Error Handling:**
- Raise ValueError if multiplier < 2 or not integer
- Raise ValueError if df missing required OHLCV columns
- Raise ValueError if df.index not monotonic increasing
- Propagate resampling errors

**SLOs:**
- Correctness: Resampled bars = base_bars / multiplier (±1)
- Correctness: Forward-fill preserves non-anticipative (verify via test)
- Observability: Log resampling operations with timestamps

### Task 3: CrossIntervalFeatures Class
**File:** `src/atr_adaptive_laguerre/features/cross_interval.py`
**Lines:** ~350
**Dependencies:** pandas, numpy, scipy.stats (for mode calculation)

**Methods:**
- `__init__()`
- `extract_interactions(features_base, features_mult1, features_mult2) → pd.DataFrame[40 cols]`
- `_regime_alignment(regimes) → pd.DataFrame[6 cols]`
- `_regime_divergence(regimes, rsis) → pd.DataFrame[8 cols]`
- `_momentum_patterns(rsis, changes) → pd.DataFrame[6 cols]`
- `_crossing_patterns(crossings, regimes) → pd.DataFrame[8 cols]`
- `_temporal_patterns(regimes, bars_in_regime, bars_since) → pd.DataFrame[12 cols]`

**Error Handling:**
- Raise ValueError if input DataFrames have mismatched indices
- Raise ValueError if required columns missing
- Raise ValueError if index not monotonic
- Propagate all computation errors

**SLOs:**
- Correctness: All interaction features computable from single-interval features only
- Correctness: No lookahead (features[t] depend only on single-interval[≤t])
- Maintainability: Each extraction function ≤80 lines

### Task 4: Extend ATRAdaptiveLaguerreRSI
**File:** `src/atr_adaptive_laguerre/features/atr_adaptive_rsi.py`
**Modification:** +120 lines

**Changes:**
1. Import FeatureExpander, MultiIntervalProcessor, CrossIntervalFeatures
2. Add config fields:
   ```python
   multiplier_1: int | None = None
   multiplier_2: int | None = None
   extract_features: bool = False  # Toggle for fit_transform_features
   ```
3. Add method:
   ```python
   def fit_transform_features(self, df: pd.DataFrame) -> pd.DataFrame:
       """
       Transform OHLCV to full feature matrix.

       Returns:
           DataFrame with 27 columns (if multipliers None)
           or 121 columns (if multipliers provided)
       """
   ```

**Error Handling:**
- Raise ValueError if df invalid (propagate from fit_transform)
- Raise ValueError if multiplier_1 or multiplier_2 invalid
- Raise ValueError if multiplier_1 >= multiplier_2 (must be strictly increasing)
- Propagate all downstream errors

**SLOs:**
- Correctness: fit_transform_features output identical to manual pipeline
- Observability: Log feature extraction stages

### Task 5: Validation Tests
**File:** `tests/test_features/test_feature_expander.py`
**Lines:** ~300

**Test Cases:**
1. `test_single_interval_features_non_anticipative()` - 27 features pass progressive subset
2. `test_feature_ranges()` - All features within documented bounds
3. `test_regime_classification()` - Regime logic correct
4. `test_crossing_detection()` - Crossings detected correctly
5. `test_statistics_warmup()` - No NaN after warmup period
6. `test_multi_interval_alignment()` - Forward-fill correct
7. `test_cross_interval_interactions()` - Interactions computable
8. `test_all_features_non_anticipative()` - All 121 features non-anticipative
9. `test_error_propagation()` - Invalid inputs raise correct errors
10. `test_deterministic()` - Same input → same output

**SLOs:**
- Correctness: 100% of validation tests pass
- Maintainability: Tests isolated, no inter-test dependencies

### Task 6: Usage Examples
**File:** `examples/04_full_feature_extraction.py`
**Lines:** ~150

**Demonstrates:**
1. Single-interval feature extraction (27 columns)
2. Multi-interval feature extraction (121 columns)
3. Integration with gapless-crypto-data
4. Validation of non-anticipative guarantee
5. Feature correlation analysis
6. IC calculation per feature

**File:** `examples/05_seq2seq_feature_preparation.py`
**Lines:** ~200

**Demonstrates:**
1. Fetch multi-interval OHLCV
2. Extract 121 features
3. Create target variable (k-step-ahead returns)
4. Train/test split (temporal)
5. Feature importance analysis
6. Prepare for LSTM/Transformer input

**SLOs:**
- Availability: Examples run without errors on sample data
- Observability: Examples include print statements showing shapes, types

### Task 7: Documentation
**File:** `docs/FEATURE_ENGINEERING_GUIDE.md`
**Lines:** ~400

**Sections:**
1. Feature categories overview
2. Non-anticipative guarantee explanation
3. Multi-interval architecture
4. Cross-interval interaction rationale
5. API reference (all 121 features)
6. Integration with gapless-crypto-data
7. Seq2seq preparation workflow

**File:** `docs/README.md`
**Modification:** Add "Feature Engineering" section

**SLOs:**
- Correctness: All code examples run without errors
- Observability: Include expected outputs for all examples

---

## Validation Criteria

### Non-Anticipative Guarantee
**Test:** Progressive subset validation for all 121 features
**Method:**
```python
for col in feature_df.columns:
    assert validate_non_anticipative(
        feature_fn=lambda df: extractor.fit_transform_features(df)[col],
        df=test_df,
        n_tests=50
    )
```
**Success:** All features pass (0 failures)

### Feature Ranges
**Test:** Verify all features within documented bounds
**Method:**
```python
assert (feature_df['rsi_base'] >= 0).all() and (feature_df['rsi_base'] <= 1).all()
assert feature_df['regime_base'].isin([0, 1, 2]).all()
# ... for all 121 features
```
**Success:** 100% of values in valid range

### Numerical Stability
**Test:** NaN count after warmup
**Method:**
```python
warmup = max(stats_window, multiplier_2)
assert feature_df.iloc[warmup:].isna().sum().sum() / (len(feature_df) - warmup) < 0.0001
```
**Success:** <0.01% NaN rate

### Performance
**Test:** Extraction time for 10k bars
**Method:**
```python
import time
start = time.time()
features = extractor.fit_transform_features(df_10k)
elapsed = time.time() - start
```
**Target:** <500ms (not SLO, but nice-to-have)

---

## Dependencies

### Required Packages
- pandas >= 2.0
- numpy >= 1.26
- scipy >= 1.10 (for stats.mode in regime_majority)

### Internal Dependencies
- `atr_adaptive_laguerre.core.*` (existing)
- `atr_adaptive_laguerre.features.base` (existing)
- `atr_adaptive_laguerre.validation.non_anticipative` (existing)

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0.0 | 2025-10-06 | Initial plan: 121 features (27 single + 54 multi + 40 interactions) | System |

---

## Notes

1. **Cross-interval interactions are the primary value** of multi-interval features
2. Forward-fill alignment preserves non-anticipative guarantee
3. All features must be derivable from RSI values only (no external data)
4. Integer multiples constraint enforced at config level
5. Error handling: raise and propagate, no silent failures
