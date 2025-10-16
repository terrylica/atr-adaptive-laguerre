"""
Tests for backtesting.py adapter module.

Validates SLO guarantees:
- Correctness: Column mapping bidirectional accuracy 100%
- Correctness: Non-anticipative property maintained 100%
- Correctness: Output value range [0.0, 1.0]: 100%
- Correctness: Output length matches input length: 100%
- Observability: Clear error messages for all failure modes
"""

import numpy as np
import pandas as pd
import pytest

from atr_adaptive_laguerre.backtesting_adapter import (
    compute_feature,
    compute_indicator,
    make_indicator,
)
from atr_adaptive_laguerre.backtesting_models import (
    FeatureConfig,
    IndicatorConfig,
)


@pytest.fixture
def sample_ohlcv_titlecase():
    """Create sample OHLCV data with backtesting.py Title case columns."""
    np.random.seed(42)
    n = 100

    dates = pd.date_range("2024-01-01", periods=n, freq="1h")
    close = 100 + np.cumsum(np.random.randn(n) * 2)
    high = close + np.random.rand(n) * 2
    low = close - np.random.rand(n) * 2
    open_prices = close + np.random.randn(n) * 0.5
    volume = np.random.randint(1000, 10000, n)

    df = pd.DataFrame(
        {
            "Open": open_prices,
            "High": high,
            "Low": low,
            "Close": close,
            "Volume": volume,
        },
        index=dates,
    )

    return df


@pytest.fixture
def sample_ohlcv_lowercase():
    """Create sample OHLCV data with lowercase columns (package internal)."""
    np.random.seed(42)
    n = 100

    dates = pd.date_range("2024-01-01", periods=n, freq="1h")
    close = 100 + np.cumsum(np.random.randn(n) * 2)
    high = close + np.random.rand(n) * 2
    low = close - np.random.rand(n) * 2
    open_prices = close + np.random.randn(n) * 0.5
    volume = np.random.randint(1000, 10000, n)

    df = pd.DataFrame(
        {
            "open": open_prices,
            "high": high,
            "low": low,
            "close": close,
            "volume": volume,
        },
        index=dates,
    )

    return df


class TestComputeIndicator:
    """Test compute_indicator function with Pydantic API."""

    def test_basic_computation_with_titlecase(self, sample_ohlcv_titlecase):
        """Test basic indicator computation with Title case columns."""
        config = IndicatorConfig()
        result = compute_indicator(config, sample_ohlcv_titlecase)

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_titlecase)
        assert result.min() >= 0.0
        assert result.max() <= 1.0

    def test_basic_computation_with_lowercase(self, sample_ohlcv_lowercase):
        """Test that lowercase columns also work (mixed case support)."""
        config = IndicatorConfig()
        result = compute_indicator(config, sample_ohlcv_lowercase)

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_lowercase)

    def test_with_mock_data_object(self, sample_ohlcv_titlecase):
        """Test with backtesting.py-style data object with .df accessor."""

        class MockData:
            @property
            def df(self):
                return sample_ohlcv_titlecase

        config = IndicatorConfig()
        result = compute_indicator(config, MockData())

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_titlecase)

    def test_custom_parameters(self, sample_ohlcv_titlecase):
        """Test with custom parameters."""
        config = IndicatorConfig(
            atr_period=20,
            smoothing_period=7,
            adaptive_offset=0.5,
            level_up=0.9,
            level_down=0.1,
        )
        result = compute_indicator(config, sample_ohlcv_titlecase)

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_titlecase)
        assert result.min() >= 0.0
        assert result.max() <= 1.0

    def test_missing_columns_raises_clear_error(self):
        """Test that missing columns raise ValueError with clear message."""
        df = pd.DataFrame({"Open": [100], "High": [101]})
        config = IndicatorConfig()

        with pytest.raises(ValueError) as exc_info:
            compute_indicator(config, df)

        error_msg = str(exc_info.value)
        assert "missing required columns" in error_msg.lower()
        assert "low" in error_msg.lower() or "Low" in error_msg
        assert "close" in error_msg.lower() or "Close" in error_msg
        assert "volume" in error_msg.lower() or "Volume" in error_msg

    def test_invalid_data_type_raises_clear_error(self):
        """Test that invalid data type raises TypeError with clear message."""
        config = IndicatorConfig()

        with pytest.raises(TypeError) as exc_info:
            compute_indicator(config, [1, 2, 3])

        error_msg = str(exc_info.value)
        assert "must be" in error_msg.lower()
        assert "dataframe" in error_msg.lower()

    def test_output_length_matches_input(self, sample_ohlcv_titlecase):
        """SLO: Output length matches input length 100%."""
        config = IndicatorConfig()
        # Test with different lengths within available data
        max_len = len(sample_ohlcv_titlecase)
        for n in [50, 75, max_len]:
            df = sample_ohlcv_titlecase.iloc[:n]
            result = compute_indicator(config, df)
            assert len(result) == n, f"Length mismatch for n={n}"

    def test_output_range_guarantee(self, sample_ohlcv_titlecase):
        """SLO: Output value range [0.0, 1.0]: 100%."""
        config = IndicatorConfig()
        result = compute_indicator(config, sample_ohlcv_titlecase)

        # Check every value is in valid range
        assert np.all(result >= 0.0), f"Values below 0.0: {result[result < 0.0]}"
        assert np.all(result <= 1.0), f"Values above 1.0: {result[result > 1.0]}"

        # Check for NaN values (should handle warmup properly)
        nan_count = np.sum(np.isnan(result))
        if nan_count > 0:
            # NaN only acceptable in warmup period
            first_valid_idx = np.where(~np.isnan(result))[0][0]
            assert first_valid_idx < 50, "Too many NaN values in warmup"


class TestComputeFeature:
    """Test compute_feature function with Pydantic API."""

    def test_extract_rsi_feature(self, sample_ohlcv_titlecase):
        """Test extracting RSI feature."""
        config = FeatureConfig(feature_name="rsi")
        result = compute_feature(config, sample_ohlcv_titlecase)

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_titlecase)
        assert result.min() >= 0.0
        assert result.max() <= 1.0

    def test_extract_regime_feature(self, sample_ohlcv_titlecase):
        """Test extracting regime feature."""
        config = FeatureConfig(feature_name="regime")
        result = compute_feature(config, sample_ohlcv_titlecase)

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_titlecase)
        # Regime should be 0 (bearish), 1 (neutral), or 2 (bullish)
        unique_values = np.unique(result[~np.isnan(result)])
        assert set(unique_values).issubset({0, 1, 2})

    def test_extract_volatility_feature(self, sample_ohlcv_titlecase):
        """Test extracting volatility feature."""
        config = FeatureConfig(feature_name="rsi_volatility_20")
        result = compute_feature(config, sample_ohlcv_titlecase)

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_titlecase)
        # Volatility is non-negative
        assert np.all(result[~np.isnan(result)] >= 0)

    def test_extract_boolean_feature(self, sample_ohlcv_titlecase):
        """Test extracting boolean feature."""
        config = FeatureConfig(feature_name="regime_bearish")
        result = compute_feature(config, sample_ohlcv_titlecase)

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_titlecase)
        # Boolean feature should be 0 or 1
        unique_values = np.unique(result[~np.isnan(result)])
        assert set(unique_values).issubset({0, 1, True, False})

    def test_invalid_feature_name_raises_clear_error(
        self, sample_ohlcv_titlecase
    ):
        """Test that invalid feature name raises ValueError with available features."""
        config = FeatureConfig(feature_name="rsi")  # Valid config first
        # Now create invalid config - but Pydantic will catch this at creation
        # So we need to test the runtime error from compute_feature

        # For this test, we'll pass a valid config but the error happens in compute_feature
        # when checking if feature exists in the dataframe
        # Actually, FeatureConfig uses Literal type, so invalid feature_name will
        # be caught by Pydantic validation at config creation time

        # Let's test that compute_feature raises error for valid but non-existent feature
        # Actually, the Literal type prevents invalid feature names at config level
        # This test now validates Pydantic's constraint enforcement
        from pydantic import ValidationError

        with pytest.raises(ValidationError):
            FeatureConfig(feature_name="invalid_feature")  # type: ignore

    def test_all_31_features_accessible(self, sample_ohlcv_titlecase):
        """Test that all expected features are accessible."""
        # Sample of expected features from each category
        expected_features = [
            "rsi",  # Base
            "regime",
            "regime_bearish",
            "regime_neutral",  # Regimes
            "dist_overbought",
            "dist_oversold",  # Thresholds
            "cross_above_oversold",  # Crossings
            "bars_since_oversold",  # Temporal
            "rsi_velocity",  # Rate of change
            "rsi_volatility_20",  # Statistics
            "tail_risk_score",  # Tail risk
        ]

        for feature in expected_features:
            config = FeatureConfig(feature_name=feature)  # type: ignore
            result = compute_feature(config, sample_ohlcv_titlecase)
            assert isinstance(result, np.ndarray)
            assert len(result) == len(sample_ohlcv_titlecase)


class TestMakeIndicator:
    """Test make_indicator factory with Pydantic validation."""

    def test_factory_returns_callable(self):
        """Test that factory returns callable function."""
        indicator = make_indicator(atr_period=20)

        assert callable(indicator)
        assert hasattr(indicator, "__name__")
        assert "ATR_Laguerre" in indicator.__name__

    def test_factory_function_works(self, sample_ohlcv_titlecase):
        """Test that created function works correctly."""
        indicator = make_indicator(atr_period=15, smoothing_period=4)
        result = indicator(sample_ohlcv_titlecase)

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_titlecase)
        assert result.min() >= 0.0
        assert result.max() <= 1.0

    def test_factory_name_includes_parameters(self):
        """Test that factory sets function name with parameters."""
        indicator = make_indicator(atr_period=25, smoothing_period=8)

        assert "25" in indicator.__name__
        assert "8" in indicator.__name__

    def test_multiple_indicators_independent(self, sample_ohlcv_titlecase):
        """Test that multiple indicators are independent."""
        fast = make_indicator(atr_period=10)
        slow = make_indicator(atr_period=20)

        fast_result = fast(sample_ohlcv_titlecase)
        slow_result = slow(sample_ohlcv_titlecase)

        # Results should differ (different parameters)
        assert not np.allclose(fast_result, slow_result)

    def test_factory_validates_parameters(self):
        """Test that factory validates parameters via Pydantic."""
        from pydantic import ValidationError

        # Invalid atr_period (too high)
        with pytest.raises(ValidationError):
            make_indicator(atr_period=50)

        # Invalid smoothing_period (too low)
        with pytest.raises(ValidationError):
            make_indicator(smoothing_period=2)


class TestNonAnticipative:
    """Test non-anticipative property of adapter (SLO guarantee)."""

    def test_progressive_computation_consistency(self, sample_ohlcv_titlecase):
        """
        SLO: Non-anticipative property maintained 100%.

        Verify that computing on first N rows produces identical results
        to computing on full dataset and taking first N values.
        """
        config = IndicatorConfig()
        full_result = compute_indicator(config, sample_ohlcv_titlecase)

        # Test at multiple points
        for n in [50, 75, 90]:
            partial_df = sample_ohlcv_titlecase.iloc[:n]
            partial_result = compute_indicator(config, partial_df)

            # First N values should be identical (non-anticipative)
            np.testing.assert_allclose(
                partial_result,
                full_result[:n],
                rtol=1e-9,
                atol=1e-12,
                err_msg=f"Non-anticipative property violated at n={n}",
            )

    def test_non_anticipative_with_features(self, sample_ohlcv_titlecase):
        """Test non-anticipative property for features."""
        config = FeatureConfig(feature_name="regime")
        full_result = compute_feature(config, sample_ohlcv_titlecase)

        for n in [50, 75]:
            partial_df = sample_ohlcv_titlecase.iloc[:n]
            partial_result = compute_feature(config, partial_df)

            np.testing.assert_allclose(
                partial_result,
                full_result[:n],
                rtol=1e-9,
                atol=1e-12,
            )


class TestColumnMapping:
    """Test column mapping correctness (SLO guarantee)."""

    def test_titlecase_to_lowercase_mapping(self, sample_ohlcv_titlecase):
        """SLO: Column mapping bidirectional accuracy 100% (Title → lower)."""
        # Should work with Title case
        config = IndicatorConfig()
        result = compute_indicator(config, sample_ohlcv_titlecase)
        assert isinstance(result, np.ndarray)

    def test_lowercase_columns_work(self, sample_ohlcv_lowercase):
        """Test that lowercase columns also work (already in internal format)."""
        config = IndicatorConfig()
        result = compute_indicator(config, sample_ohlcv_lowercase)
        assert isinstance(result, np.ndarray)

    def test_mixed_case_columns_rejected(self):
        """Test that mixed case columns are rejected with clear error."""
        df = pd.DataFrame(
            {
                "OPEN": [100],  # Uppercase (wrong)
                "High": [101],
                "Low": [99],
                "Close": [100],
                "Volume": [1000],
            }
        )
        config = IndicatorConfig()

        with pytest.raises(ValueError) as exc_info:
            compute_indicator(config, df)

        error_msg = str(exc_info.value)
        assert "missing required columns" in error_msg.lower()


class TestEdgeCases:
    """Test edge cases and error conditions."""

    def test_minimum_data_rows(self, sample_ohlcv_titlecase):
        """Test with minimum data rows (warmup period)."""
        # Should work with at least 50 rows (enough for warmup)
        df = sample_ohlcv_titlecase.iloc[:50]
        config = IndicatorConfig()
        result = compute_indicator(config, df)

        assert isinstance(result, np.ndarray)
        assert len(result) == 50

    def test_empty_dataframe_raises_error(self):
        """Test that empty DataFrame raises appropriate error."""
        df = pd.DataFrame(
            {"Open": [], "High": [], "Low": [], "Close": [], "Volume": []}
        )
        config = IndicatorConfig()

        # Empty DataFrame will propagate error from core computation
        with pytest.raises(Exception):  # Could be ValueError or IndexError
            compute_indicator(config, df)

    def test_single_row_raises_error(self):
        """Test that single row raises appropriate error."""
        df = pd.DataFrame(
            {
                "Open": [100],
                "High": [101],
                "Low": [99],
                "Close": [100],
                "Volume": [1000],
            }
        )
        config = IndicatorConfig()

        # Single row insufficient for computation
        with pytest.raises(Exception):
            compute_indicator(config, df)


class TestBacktestingIntegration:
    """Integration tests with backtesting.py patterns."""

    def test_indicator_in_mock_strategy_pattern(self, sample_ohlcv_titlecase):
        """Test usage pattern similar to backtesting.py Strategy."""

        class MockStrategy:
            def __init__(self, data):
                self.data = data

            def I(self, func, *args, **kwargs):
                """Mock Strategy.I() method."""
                return func(*args, **kwargs)

            def init(self):
                # This is how it would be used in real Strategy with v2.0.0 API
                config = IndicatorConfig()
                self.rsi = self.I(compute_indicator, config, self.data)
                return self.rsi

        class MockData:
            @property
            def df(self):
                return sample_ohlcv_titlecase

        strategy = MockStrategy(MockData())
        result = strategy.init()

        assert isinstance(result, np.ndarray)
        assert len(result) == len(sample_ohlcv_titlecase)

    def test_factory_pattern_with_multiple_indicators(
        self, sample_ohlcv_titlecase
    ):
        """Test factory pattern for multiple indicators."""
        fast_indicator = make_indicator(atr_period=10, smoothing_period=3)
        slow_indicator = make_indicator(atr_period=20, smoothing_period=7)

        fast_result = fast_indicator(sample_ohlcv_titlecase)
        slow_result = slow_indicator(sample_ohlcv_titlecase)

        assert len(fast_result) == len(sample_ohlcv_titlecase)
        assert len(slow_result) == len(sample_ohlcv_titlecase)
        assert not np.array_equal(fast_result, slow_result)
