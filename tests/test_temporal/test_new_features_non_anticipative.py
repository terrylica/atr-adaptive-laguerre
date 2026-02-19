"""
Non-anticipative progressive subset tests for all 12 new features (v2.3.0).

Closes audit coverage gap: existing test_feature_expander.py only validates base RSI,
not FeatureExpander-level intermediate features. This test validates at the
fit_transform_features() layer.

Methodology:
    For t in [min_lookback+50, 75%, 90%, 100%]:
        features_partial = indicator.fit_transform_features(df[:t])
        features_full = indicator.fit_transform_features(df)
        for each of 12 new feature columns (with _base suffix):
            assert features_partial[col].iloc[:t] == features_full[col].iloc[:t]

SLOs:
- Correctness: 100% - Any lookahead violation fails immediately
- Observability: Detailed error with column name, index, and values

Error Handling: raise_and_propagate
"""

import numpy as np
import pandas as pd
import pytest

from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig


# The 12 new features added in v2.3.0
NEW_FEATURES = [
    "adaptive_coeff",
    "adaptive_coeff_roc_1",
    "gamma_value",
    "gamma_spread",
    "laguerre_spread",
    "laguerre_mid_convergence",
    "laguerre_slope",
    "atr_range_width",
    "efficiency_ratio",
    "efficiency_trend",
    "cycle_phase",
    "cycle_phase_changed",
]


@pytest.fixture
def sample_ohlcv() -> pd.DataFrame:
    """Generate sample OHLCV data with sufficient length for progressive subset testing."""
    np.random.seed(42)
    n_bars = 600

    base_price = 100 + np.cumsum(np.random.randn(n_bars) * 0.5)
    close = base_price
    open_ = close + np.random.randn(n_bars) * 0.3
    high = np.maximum(close, open_) + np.abs(np.random.randn(n_bars) * 0.2)
    low = np.minimum(close, open_) - np.abs(np.random.randn(n_bars) * 0.2)
    volume = np.random.randint(1000, 10000, n_bars).astype(float)
    dates = pd.date_range("2024-01-01", periods=n_bars, freq="5min")

    return pd.DataFrame(
        {
            "date": dates,
            "open": open_,
            "high": high,
            "low": low,
            "close": close,
            "volume": volume,
        }
    )


class TestNewFeaturesNonAnticipative:
    """
    Progressive subset tests for 12 new intermediate-based features.

    Tests single-interval mode (43 features) where base features are directly
    comparable across subsets without resampling artifacts.
    """

    def test_single_interval_new_features_non_anticipative(
        self, sample_ohlcv: pd.DataFrame
    ) -> None:
        """
        Test all 12 new features are non-anticipative in single-interval mode.

        Progressive subset: compute features on df[:t] for multiple t values,
        verify overlapping bars produce identical values.
        """
        config = ATRAdaptiveLaguerreRSIConfig.single_interval()
        indicator = ATRAdaptiveLaguerreRSI(config)

        features_full = indicator.fit_transform_features(sample_ohlcv)
        assert features_full.shape[1] == 43

        # Verify all 12 new features are present
        for feat in NEW_FEATURES:
            assert feat in features_full.columns, f"Missing new feature: {feat}"

        # Progressive subset lengths
        test_lengths = [
            indicator.min_lookback + 50,
            int(len(sample_ohlcv) * 0.75),
            int(len(sample_ohlcv) * 0.9),
            len(sample_ohlcv),
        ]

        for test_len in test_lengths:
            features_subset = indicator.fit_transform_features(
                sample_ohlcv.iloc[:test_len]
            )

            for col in NEW_FEATURES:
                full_vals = features_full[col].iloc[:test_len].values
                subset_vals = features_subset[col].values

                if not np.allclose(
                    full_vals, subset_vals, rtol=1e-9, atol=1e-12, equal_nan=True
                ):
                    # Find first mismatch for diagnostic
                    diffs = np.abs(full_vals - subset_vals)
                    max_diff = np.nanmax(diffs)
                    diff_idx = np.nanargmax(diffs)
                    raise AssertionError(
                        f"Lookahead bias in new feature '{col}' at subset length {test_len}!\n"
                        f"Max diff: {max_diff:.2e} at index {diff_idx}\n"
                        f"Full[{diff_idx}]={full_vals[diff_idx]:.6f}, "
                        f"Subset[{diff_idx}]={subset_vals[diff_idx]:.6f}"
                    )

    def test_multi_interval_base_new_features_non_anticipative(
        self, sample_ohlcv: pd.DataFrame
    ) -> None:
        """
        Test 12 new features with _base suffix are non-anticipative in multi-interval mode.

        Base interval features should be identical regardless of dataset length.
        Mult1/mult2 features are excluded because resampling creates history-dependent
        behavior (not lookahead — just different warmup).
        """
        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=3, multiplier_2=12, filter_redundancy=False
        )
        indicator = ATRAdaptiveLaguerreRSI(config)

        features_full = indicator.fit_transform_features(sample_ohlcv)
        assert features_full.shape[1] == 169

        # Test _base suffix versions of the 12 new features
        base_new_features = [f"{feat}_base" for feat in NEW_FEATURES]
        for feat in base_new_features:
            assert feat in features_full.columns, f"Missing base feature: {feat}"

        test_lengths = [
            int(len(sample_ohlcv) * 0.75),
            int(len(sample_ohlcv) * 0.9),
            len(sample_ohlcv),
        ]

        for test_len in test_lengths:
            features_subset = indicator.fit_transform_features(
                sample_ohlcv.iloc[:test_len]
            )

            for col in base_new_features:
                full_vals = features_full[col].iloc[:test_len].values
                subset_vals = features_subset[col].values

                if not np.allclose(
                    full_vals, subset_vals, rtol=1e-9, atol=1e-12, equal_nan=True
                ):
                    diffs = np.abs(full_vals - subset_vals)
                    max_diff = np.nanmax(diffs)
                    diff_idx = np.nanargmax(diffs)
                    raise AssertionError(
                        f"Lookahead bias in base feature '{col}' at length {test_len}!\n"
                        f"Max diff: {max_diff:.2e} at index {diff_idx}\n"
                        f"Full[{diff_idx}]={full_vals[diff_idx]:.6f}, "
                        f"Subset[{diff_idx}]={subset_vals[diff_idx]:.6f}"
                    )


class TestNewFeatureRanges:
    """Validate value ranges for all 12 new features."""

    def test_feature_ranges(self, sample_ohlcv: pd.DataFrame) -> None:
        """
        Test all 12 new features have expected value ranges.

        Range checks:
        - adaptive_coeff ∈ [0, 1]
        - gamma_value ∈ (0, 1)
        - atr_range_width ∈ [0, 1)
        - efficiency_ratio ∈ [0, 1]
        - efficiency_trend ∈ {0, 1}
        - cycle_phase ∈ {0, 1, 2, 3}
        - cycle_phase_changed ∈ {0, 1}
        """
        config = ATRAdaptiveLaguerreRSIConfig.single_interval()
        indicator = ATRAdaptiveLaguerreRSI(config)
        features = indicator.fit_transform_features(sample_ohlcv)

        # Skip warmup period
        warmup = indicator.min_lookback
        f = features.iloc[warmup:]

        # adaptive_coeff ∈ [0, 1]
        assert f["adaptive_coeff"].min() >= 0, "adaptive_coeff below 0"
        assert f["adaptive_coeff"].max() <= 1, "adaptive_coeff above 1"

        # gamma_value ∈ (0, 1)
        assert f["gamma_value"].min() > 0, "gamma_value not > 0"
        assert f["gamma_value"].max() < 1, "gamma_value not < 1"

        # atr_range_width ∈ [0, 1)
        assert f["atr_range_width"].min() >= 0, "atr_range_width below 0"
        assert f["atr_range_width"].max() < 1, "atr_range_width >= 1"

        # efficiency_ratio ∈ [0, 1]
        assert f["efficiency_ratio"].min() >= 0, "efficiency_ratio below 0"
        assert f["efficiency_ratio"].max() <= 1, "efficiency_ratio above 1"

        # efficiency_trend ∈ {0, 1}
        assert set(f["efficiency_trend"].unique()) <= {0, 1}, "efficiency_trend not binary"

        # cycle_phase ∈ {0, 1, 2, 3}
        assert set(f["cycle_phase"].unique()) <= {0, 1, 2, 3}, "cycle_phase out of range"

        # cycle_phase_changed ∈ {0, 1}
        assert set(f["cycle_phase_changed"].unique()) <= {0, 1}, "cycle_phase_changed not binary"

    def test_no_nan_after_warmup(self, sample_ohlcv: pd.DataFrame) -> None:
        """
        Test no NaN values in new features after warmup period.

        Warmup bars may have NaN (expected), but post-warmup must be clean.
        """
        config = ATRAdaptiveLaguerreRSIConfig.single_interval()
        indicator = ATRAdaptiveLaguerreRSI(config)
        features = indicator.fit_transform_features(sample_ohlcv)

        warmup = indicator.min_lookback
        post_warmup = features.iloc[warmup:]

        for feat in NEW_FEATURES:
            nan_count = post_warmup[feat].isna().sum()
            assert nan_count == 0, (
                f"Feature '{feat}' has {nan_count} NaN values after warmup (row {warmup}+)"
            )
