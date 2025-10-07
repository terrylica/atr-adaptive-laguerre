"""
Validation tests for redundancy filtering (121→79 features).

SLOs:
- Availability: 100% (all tests must pass in CI)
- Correctness: 100% (exactly 42 features dropped, 79 retained)
- Observability: Full type hints, descriptive test names
- Maintainability: ≤50 lines per test, single responsibility

Error Handling: raise_and_propagate
- All tests must fail loudly if feature count mismatches
- No silent failures or approximate assertions
"""

import numpy as np
import pandas as pd
import pytest

from atr_adaptive_laguerre.features.atr_adaptive_rsi import (
    ATRAdaptiveLaguerreRSI,
    ATRAdaptiveLaguerreRSIConfig,
)
from atr_adaptive_laguerre.features.redundancy_filter import RedundancyFilter


@pytest.fixture
def sample_121_features() -> pd.DataFrame:
    """
    Generate sample 121-feature DataFrame for testing.

    Returns DataFrame with all 121 feature names from multi-interval mode,
    including the 42 redundant features that should be filtered.
    """
    # Generate all 121 feature names (27 × 3 intervals + 40 cross-interval)
    # Base features (27)
    base_features = [
        "rsi",
        "regime",
        "regime_bearish",
        "regime_neutral",
        "regime_bullish",
        "regime_changed",
        "bars_in_regime",
        "regime_strength",
        "dist_overbought",
        "dist_oversold",
        "dist_midline",
        "abs_dist_overbought",
        "abs_dist_oversold",
        "cross_above_oversold",
        "cross_below_overbought",
        "cross_above_midline",
        "cross_below_midline",
        "bars_since_oversold",
        "bars_since_overbought",
        "bars_since_extreme",
        "rsi_change_1",
        "rsi_change_5",
        "rsi_velocity",
        "rsi_percentile_20",
        "rsi_zscore_20",
        "rsi_volatility_20",
        "rsi_range_20",
    ]

    # Create column names for 3 intervals
    all_features = []
    for suffix in ["_base", "_mult1", "_mult2"]:
        all_features.extend([f + suffix for f in base_features])

    # Add cross-interval features (40)
    cross_features = [
        "all_intervals_bullish",
        "all_intervals_bearish",
        "all_intervals_neutral",
        "regime_agreement_count",
        "regime_majority",
        "regime_unanimity",
        "base_bull_higher_bear",
        "base_bear_higher_bull",
        "divergence_strength",
        "divergence_direction",
        "base_extreme_higher_neutral",
        "base_neutral_higher_extreme",
        "gradient_up",
        "gradient_down",
        "rsi_spread_base_mult1",
        "rsi_spread_base_mult2",
        "rsi_spread_mult1_mult2",
        "rsi_range_across_intervals",
        "rsi_skew_across_intervals",
        "momentum_consistency",
        "all_intervals_crossed_overbought",
        "all_intervals_crossed_oversold",
        "any_interval_crossed_overbought",
        "any_interval_crossed_oversold",
        "cascade_crossing_up",
        "cascade_crossing_down",
        "higher_crossed_first",
        "momentum_direction",
        "regime_persistence_ratio",
        "regime_change_cascade",
        "alignment_duration",
        "regime_stability_score",
        "regime_transition_pattern",
        "higher_interval_leads",
        "interval_momentum_agreement",
        "temporal_regime_cascade",
        "higher_interval_confirms",
        "regime_propagation_speed",
        "multi_interval_regime_strength",
        "cascade_completion_ratio",
    ]
    all_features.extend(cross_features)

    # Generate random data for all 121 features
    n_rows = 100
    data = {col: np.random.rand(n_rows) for col in all_features}

    return pd.DataFrame(data)


class TestRedundancyFilter:
    """Test RedundancyFilter class (42 features removed)."""

    def test_filter_disabled_by_default(
        self, sample_121_features: pd.DataFrame
    ) -> None:
        """
        Test filtering is disabled when apply_filter=False.

        Backward compatibility: Default behavior returns unchanged DataFrame.
        """
        filtered = RedundancyFilter.filter(sample_121_features, apply_filter=False)

        # Verify no columns removed
        assert filtered.shape == sample_121_features.shape
        assert list(filtered.columns) == list(sample_121_features.columns)
        pd.testing.assert_frame_equal(filtered, sample_121_features)

    def test_filter_removes_exactly_42_features(
        self, sample_121_features: pd.DataFrame
    ) -> None:
        """
        Test filtering removes exactly 42 redundant features.

        Expected: 121 features → 79 features (42 removed).
        """
        filtered = RedundancyFilter.filter(sample_121_features, apply_filter=True)

        # Verify feature count
        assert sample_121_features.shape[1] == 121
        assert filtered.shape[1] == 79
        assert filtered.shape[0] == sample_121_features.shape[0]  # Rows unchanged

    def test_correct_features_removed(
        self, sample_121_features: pd.DataFrame
    ) -> None:
        """
        Test that correct redundant features are removed.

        Verify all 42 features in REDUNDANT_FEATURES list are dropped.
        """
        filtered = RedundancyFilter.filter(sample_121_features, apply_filter=True)

        redundant_features = RedundancyFilter.get_redundant_features()

        # Verify redundant features absent from filtered DataFrame
        for feature in redundant_features:
            if feature in sample_121_features.columns:
                assert feature not in filtered.columns, f"Feature '{feature}' not removed"

        # Verify non-redundant features present
        retained_features = set(sample_121_features.columns) - set(redundant_features)
        for feature in retained_features:
            assert feature in filtered.columns, f"Non-redundant feature '{feature}' incorrectly removed"

    def test_get_redundant_features_returns_42(self) -> None:
        """
        Test get_redundant_features returns exactly 42 feature names.

        Validates REDUNDANT_FEATURES list completeness.
        """
        redundant = RedundancyFilter.get_redundant_features()

        assert isinstance(redundant, list)
        assert len(redundant) == 42
        assert all(isinstance(f, str) for f in redundant)

    def test_n_features_after_filtering_calculation(self) -> None:
        """
        Test n_features_after_filtering calculation is correct.

        Test cases:
        - 27 features → 27 (no filtering in single-interval)
        - 121 features → 79 (removes 42 in multi-interval)
        """
        # Single-interval mode (no filtering)
        assert RedundancyFilter.n_features_after_filtering(27) == 27

        # Multi-interval mode (removes 42)
        assert RedundancyFilter.n_features_after_filtering(121) == 79

        # Unknown mode (return as-is)
        assert RedundancyFilter.n_features_after_filtering(100) == 100

    def test_filter_handles_missing_columns_gracefully(self) -> None:
        """
        Test filter handles DataFrames without redundant features.

        If DataFrame already filtered or in single-interval mode,
        filter should return unchanged (no KeyError).
        """
        # Create DataFrame with only non-redundant features
        # (features NOT in REDUNDANT_FEATURES list)
        df_no_redundant = pd.DataFrame(
            {
                "rsi_change_5_base": np.random.rand(50),
                "regime_bearish_base": np.random.randint(0, 2, 50),
                "bars_since_extreme_base": np.random.randint(0, 100, 50),
            }
        )

        # Should not raise error, returns unchanged
        filtered = RedundancyFilter.filter(df_no_redundant, apply_filter=True)
        pd.testing.assert_frame_equal(filtered, df_no_redundant)

    def test_filter_handles_partial_redundant_features(self) -> None:
        """
        Test filter handles DataFrames with only some redundant features.

        Scenario: Custom feature selection already removed some redundant features.
        """
        # Create DataFrame with mix of redundant and non-redundant
        df_partial = pd.DataFrame(
            {
                "rsi_base": np.random.rand(50),  # Redundant
                "dist_midline_base": np.random.rand(50),  # Redundant
                "rsi_change_5_base": np.random.rand(50),  # Non-redundant
                "regime_bearish_base": np.random.randint(0, 2, 50),  # Non-redundant
            }
        )

        filtered = RedundancyFilter.filter(df_partial, apply_filter=True)

        # Should remove only redundant features present
        assert "rsi_base" not in filtered.columns
        assert "dist_midline_base" not in filtered.columns
        assert "rsi_change_5_base" in filtered.columns
        assert "regime_bearish_base" in filtered.columns
        assert filtered.shape[1] == 2  # 4 → 2 features


class TestRedundancyFilterIntegration:
    """Test RedundancyFilter integration with ATRAdaptiveLaguerreRSI."""

    @pytest.fixture
    def sample_ohlcv(self) -> pd.DataFrame:
        """Generate sample OHLCV data for integration tests."""
        np.random.seed(42)
        n_bars = 600

        base_price = 100 + np.cumsum(np.random.randn(n_bars) * 0.5)
        close = base_price
        open_ = close + np.random.randn(n_bars) * 0.3
        high = np.maximum(close, open_) + np.abs(np.random.randn(n_bars) * 0.2)
        low = np.minimum(close, open_) - np.abs(np.random.randn(n_bars) * 0.2)
        volume = np.random.randint(1000, 10000, n_bars)
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

    def test_config_filter_redundancy_default_true(self) -> None:
        """
        Test filter_redundancy defaults to True.

        Default behavior: 79 features (redundancy filtering enabled).
        """
        config = ATRAdaptiveLaguerreRSIConfig.multi_interval()
        assert config.filter_redundancy is True

    def test_n_features_without_filtering(self) -> None:
        """
        Test n_features returns 121 when filter_redundancy=False.

        Default behavior: Full feature set.
        """
        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(filter_redundancy=False)
        indicator = ATRAdaptiveLaguerreRSI(config)
        assert indicator.n_features == 121

    def test_n_features_with_filtering(self) -> None:
        """
        Test n_features returns 79 when filter_redundancy=True.

        Filtered mode: Reduced feature set.
        """
        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(filter_redundancy=True)
        indicator = ATRAdaptiveLaguerreRSI(config)
        assert indicator.n_features == 79

    def test_fit_transform_features_without_filtering(
        self, sample_ohlcv: pd.DataFrame
    ) -> None:
        """
        Test fit_transform_features returns 121 features when filtering disabled.

        Validates backward compatibility.
        """
        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=3, multiplier_2=12, filter_redundancy=False
        )
        indicator = ATRAdaptiveLaguerreRSI(config)
        features = indicator.fit_transform_features(sample_ohlcv)

        assert features.shape[1] == 121
        assert features.shape[0] == len(sample_ohlcv)

    def test_fit_transform_features_with_filtering(
        self, sample_ohlcv: pd.DataFrame
    ) -> None:
        """
        Test fit_transform_features returns 79 features when filtering enabled.

        Validates redundancy filtering integration.
        """
        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=3, multiplier_2=12, filter_redundancy=True
        )
        indicator = ATRAdaptiveLaguerreRSI(config)
        features = indicator.fit_transform_features(sample_ohlcv)

        assert features.shape[1] == 79
        assert features.shape[0] == len(sample_ohlcv)

        # Verify redundant features absent
        redundant = RedundancyFilter.get_redundant_features()
        for feature in redundant:
            assert feature not in features.columns

    def test_filtering_does_not_affect_single_interval(
        self, sample_ohlcv: pd.DataFrame
    ) -> None:
        """
        Test redundancy filtering has no effect in single-interval mode.

        Single-interval mode: 27 features regardless of filter_redundancy flag.
        """
        config_no_filter = ATRAdaptiveLaguerreRSIConfig.single_interval(
            filter_redundancy=False
        )
        config_with_filter = ATRAdaptiveLaguerreRSIConfig.single_interval(
            filter_redundancy=True
        )

        indicator_no_filter = ATRAdaptiveLaguerreRSI(config_no_filter)
        indicator_with_filter = ATRAdaptiveLaguerreRSI(config_with_filter)

        assert indicator_no_filter.n_features == 27
        assert indicator_with_filter.n_features == 27

    def test_filtered_features_deterministic(
        self, sample_ohlcv: pd.DataFrame
    ) -> None:
        """
        Test filtered features are deterministic.

        Same input + filter_redundancy=True → identical output.
        """
        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=3, multiplier_2=12, filter_redundancy=True
        )
        indicator = ATRAdaptiveLaguerreRSI(config)

        features_1 = indicator.fit_transform_features(sample_ohlcv)
        features_2 = indicator.fit_transform_features(sample_ohlcv)

        pd.testing.assert_frame_equal(features_1, features_2)

    def test_filtered_features_maintain_non_anticipative_property(
        self, sample_ohlcv: pd.DataFrame
    ) -> None:
        """
        Test filtered features maintain non-anticipative property.

        Filtering should not introduce lookahead bias.
        """
        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=3, multiplier_2=12, filter_redundancy=True
        )
        indicator = ATRAdaptiveLaguerreRSI(config)

        # Compute full features
        features_full = indicator.fit_transform_features(sample_ohlcv)

        # Test progressive subset (base features only)
        test_len = int(len(sample_ohlcv) * 0.75)
        features_subset = indicator.fit_transform_features(sample_ohlcv.iloc[:test_len])

        # Extract base features (suffix _base)
        base_cols = [col for col in features_full.columns if col.endswith("_base")]

        # Verify base features are non-anticipative
        for col in base_cols:
            full_vals = features_full.loc[:test_len - 1, col].values
            subset_vals = features_subset[col].values

            if not np.allclose(
                full_vals, subset_vals, rtol=1e-9, atol=1e-12, equal_nan=True
            ):
                max_diff = np.abs(full_vals - subset_vals).max()
                raise ValueError(
                    f"Lookahead bias detected in filtered feature '{col}'!\n"
                    f"Max diff: {max_diff:.2e}"
                )
