"""Tests for LaguerreFeatureProvider rangebar-py plugin.

Issue #1: https://github.com/terrylica/atr-adaptive-laguerre/issues/1
"""

from importlib.metadata import entry_points

import numpy as np
import pandas as pd
import pytest

from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSIConfig
from atr_adaptive_laguerre.rangebar_plugin import (
    DEFAULT_CONFIG,
    LaguerreFeatureProvider,
    _OUTPUT_COLUMNS,
    _load_config_from_env,
)


@pytest.fixture()
def ohlcv_bars():
    """600-bar synthetic OHLCV DataFrame (same seed as other tests)."""
    np.random.seed(42)
    n = 600
    close = 100.0 + np.cumsum(np.random.randn(n) * 0.5)
    high = close + np.abs(np.random.randn(n) * 0.3)
    low = close - np.abs(np.random.randn(n) * 0.3)
    open_ = close + np.random.randn(n) * 0.2
    volume = np.random.randint(100, 10000, size=n).astype(float)
    return pd.DataFrame({
        "open": open_,
        "high": high,
        "low": low,
        "close": close,
        "volume": volume,
    })


@pytest.fixture()
def provider():
    return LaguerreFeatureProvider()


class TestProtocolProperties:
    def test_name(self, provider):
        assert provider.name == "laguerre"

    def test_columns_exact(self, provider):
        assert provider.columns == _OUTPUT_COLUMNS
        assert len(provider.columns) == 6
        assert all(c.startswith("laguerre_") for c in provider.columns)

    def test_min_bars_positive(self, provider):
        assert provider.min_bars > 0

    def test_version_is_string(self, provider):
        v = provider.version
        assert isinstance(v, str)
        parts = v.split(".")
        assert len(parts) >= 2, f"Version '{v}' does not look like semver"


class TestEnrich:
    def test_adds_exactly_six_columns(self, provider, ohlcv_bars):
        original_cols = list(ohlcv_bars.columns)
        result = provider.enrich(ohlcv_bars, "BTCUSDT", 500)
        new_cols = [c for c in result.columns if c not in original_cols]
        assert sorted(new_cols) == sorted(_OUTPUT_COLUMNS)

    def test_existing_columns_unchanged(self, provider, ohlcv_bars):
        original_close = ohlcv_bars["close"].copy()
        result = provider.enrich(ohlcv_bars, "BTCUSDT", 500)
        pd.testing.assert_series_equal(result["close"], original_close)

    def test_valid_values_after_warmup(self, provider, ohlcv_bars):
        result = provider.enrich(ohlcv_bars, "BTCUSDT", 500)
        warmup = provider.min_bars + 10  # extra buffer for filter convergence
        for col in _OUTPUT_COLUMNS:
            after_warmup = result[col].iloc[warmup:]
            nan_count = after_warmup.isna().sum()
            assert nan_count == 0, f"{col} has {nan_count} NaNs after warmup index {warmup}"

    def test_output_dtypes(self, provider, ohlcv_bars):
        result = provider.enrich(ohlcv_bars, "BTCUSDT", 500)
        for col in _OUTPUT_COLUMNS:
            assert result[col].dtype in (np.float64, np.int64, float, int), (
                f"{col} has unexpected dtype {result[col].dtype}"
            )

    def test_same_index_preserved(self, provider, ohlcv_bars):
        ohlcv_bars.index = pd.RangeIndex(100, 700)
        result = provider.enrich(ohlcv_bars, "BTCUSDT", 500)
        assert result.index.equals(ohlcv_bars.index)

    def test_datetime_index_handled(self, provider):
        """Bars with DatetimeIndex should work without timestamp_ms column."""
        np.random.seed(99)
        n = 200
        close = 100.0 + np.cumsum(np.random.randn(n) * 0.5)
        bars = pd.DataFrame(
            {
                "open": close + np.random.randn(n) * 0.2,
                "high": close + np.abs(np.random.randn(n) * 0.3),
                "low": close - np.abs(np.random.randn(n) * 0.3),
                "close": close,
                "volume": np.random.randint(100, 10000, size=n).astype(float),
            },
            index=pd.date_range("2024-01-01", periods=n, freq="2h"),
        )
        result = provider.enrich(bars, "ETHUSDT", 300)
        assert all(c in result.columns for c in _OUTPUT_COLUMNS)

    def test_timestamp_ms_column_handled(self, provider):
        """Bars with timestamp_ms column should use it for date."""
        np.random.seed(77)
        n = 200
        close = 100.0 + np.cumsum(np.random.randn(n) * 0.5)
        bars = pd.DataFrame({
            "open": close + np.random.randn(n) * 0.2,
            "high": close + np.abs(np.random.randn(n) * 0.3),
            "low": close - np.abs(np.random.randn(n) * 0.3),
            "close": close,
            "volume": np.random.randint(100, 10000, size=n).astype(float),
            "timestamp_ms": pd.date_range("2024-01-01", periods=n, freq="2h")
            .astype(np.int64)
            // 10**6,
        })
        result = provider.enrich(bars, "SOLUSDT", 200)
        assert all(c in result.columns for c in _OUTPUT_COLUMNS)


class TestIdempotency:
    def test_double_enrich_is_noop(self, provider, ohlcv_bars):
        first = provider.enrich(ohlcv_bars, "BTCUSDT", 500)
        second = provider.enrich(first, "BTCUSDT", 500)
        # Same object reference (early return)
        assert second is first


class TestInsufficientBars:
    def test_short_bars_all_nan(self, provider):
        np.random.seed(42)
        n = 5  # Way below min_bars
        bars = pd.DataFrame({
            "open": np.random.randn(n),
            "high": np.random.randn(n),
            "low": np.random.randn(n),
            "close": np.random.randn(n),
            "volume": np.random.randint(100, 1000, size=n).astype(float),
        })
        result = provider.enrich(bars, "BTCUSDT", 500)
        for col in _OUTPUT_COLUMNS:
            assert col in result.columns
            assert result[col].isna().all(), f"{col} should be all NaN for short input"


class TestNonAnticipative:
    def test_progressive_subset_stability(self, provider, ohlcv_bars):
        """Feature at bar[i] should not change when future bars are added."""
        full = provider.enrich(ohlcv_bars.copy(), "BTCUSDT", 500)

        # Compare with prefix subset (first 300 bars)
        subset = provider.enrich(ohlcv_bars.iloc[:300].copy(), "BTCUSDT", 500)

        check_start = provider.min_bars + 20  # well past warmup
        check_end = 250  # well before subset end (avoid edge effects)

        for col in _OUTPUT_COLUMNS:
            subset_vals = subset[col].iloc[check_start:check_end].values
            full_vals = full[col].iloc[check_start:check_end].values

            both_nan = np.isnan(subset_vals) & np.isnan(full_vals)
            either_nan = np.isnan(subset_vals) | np.isnan(full_vals)
            nan_mismatch = either_nan & ~both_nan
            value_mismatch = ~either_nan & (subset_vals != full_vals)
            diff_mask = nan_mismatch | value_mismatch

            if diff_mask.any():
                idx = int(np.argmax(diff_mask)) + check_start
                pytest.fail(
                    f"Non-anticipative violation in '{col}' at index {idx}: "
                    f"subset={subset[col].iloc[idx]}, full={full[col].iloc[idx]}"
                )


class TestEntryPoint:
    def test_entry_point_discoverable(self):
        eps = entry_points(group="rangebar.feature_providers")
        names = [ep.name for ep in eps]
        assert "laguerre" in names, (
            f"Entry point 'laguerre' not found. Available: {names}"
        )

    def test_entry_point_loads(self):
        eps = entry_points(group="rangebar.feature_providers")
        laguerre_eps = [ep for ep in eps if ep.name == "laguerre"]
        assert len(laguerre_eps) == 1
        cls = laguerre_eps[0].load()
        assert cls is LaguerreFeatureProvider


class TestEnvVarOverride:
    def test_env_var_changes_config(self, monkeypatch):
        monkeypatch.setenv("RANGEBAR_LAGUERRE_ATR_PERIOD", "21")
        monkeypatch.setenv("RANGEBAR_LAGUERRE_SMOOTHING", "5")
        config = _load_config_from_env()
        assert config is not None
        assert config.atr_period == 21
        assert config.smoothing_period == 5

    def test_env_var_not_set_returns_none(self, monkeypatch):
        monkeypatch.delenv("RANGEBAR_LAGUERRE_ATR_PERIOD", raising=False)
        config = _load_config_from_env()
        assert config is None

    def test_provider_uses_env_config(self, monkeypatch):
        monkeypatch.setenv("RANGEBAR_LAGUERRE_ATR_PERIOD", "21")
        provider = LaguerreFeatureProvider()
        assert provider._config.atr_period == 21


class TestCustomConfig:
    def test_explicit_config_overrides_default(self):
        custom = ATRAdaptiveLaguerreRSIConfig(
            atr_period=21,
            smoothing_period=5,
            level_up=0.80,
            level_down=0.15,
            adaptive_offset=0.45,
        )
        provider = LaguerreFeatureProvider(config=custom)
        assert provider._config.atr_period == 21
        assert provider._config.smoothing_period == 5
