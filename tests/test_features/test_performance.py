"""Performance regression tests — assert speedup guarantees."""

import time

import numpy as np
import pandas as pd
import pytest
from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig
from atr_adaptive_laguerre.core._numba_kernel import _rolling_percentile_numba


def _generate_ohlcv(n_bars: int) -> pd.DataFrame:
    np.random.seed(42)
    close = 100 + np.cumsum(np.random.randn(n_bars) * 0.5)
    dates = pd.date_range("2024-01-01", periods=n_bars, freq="5min")
    return pd.DataFrame({
        "date": dates, "open": close + 0.1, "high": close + 0.5,
        "low": close - 0.5, "close": close, "volume": 1000,
    })


class TestPercentilePerformance:
    """Numba rolling percentile must be significantly faster than pandas lambda."""

    def test_numba_percentile_at_least_10x_faster(self) -> None:
        np.random.seed(42)
        rsi = np.random.rand(5000)
        window = 20

        # Warmup numba JIT
        _rolling_percentile_numba(rsi[:10], window)

        # Benchmark pandas lambda
        s = pd.Series(rsi)
        t0 = time.perf_counter()
        for _ in range(5):
            s.rolling(window=window, min_periods=1).apply(
                lambda x: (x[-1] > x[:-1]).sum() / len(x) * 100, raw=True
            ).fillna(50.0)
        pandas_time = (time.perf_counter() - t0) / 5

        # Benchmark numba
        t0 = time.perf_counter()
        for _ in range(5):
            _rolling_percentile_numba(rsi, window)
        numba_time = (time.perf_counter() - t0) / 5

        speedup = pandas_time / numba_time
        assert speedup >= 10, f"Expected >=10x speedup, got {speedup:.1f}x"


class TestEndToEndPerformance:
    """End-to-end fit_transform_features must complete within time ceiling."""

    def test_single_interval_5000_bars_under_50ms(self) -> None:
        df = _generate_ohlcv(5000)
        config = ATRAdaptiveLaguerreRSIConfig.single_interval()
        ind = ATRAdaptiveLaguerreRSI(config)
        # Warmup
        ind.fit_transform_features(df)
        # Benchmark
        times = []
        for _ in range(10):
            t0 = time.perf_counter()
            ind.fit_transform_features(df)
            times.append(time.perf_counter() - t0)
        median_ms = np.median(times) * 1000
        assert median_ms < 50, f"Expected <50ms, got {median_ms:.1f}ms"
