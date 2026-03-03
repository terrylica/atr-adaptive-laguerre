"""Bit-exact oracle: numba rolling percentile vs pandas rolling.apply(lambda)."""

import numpy as np
import pandas as pd
import pytest
from atr_adaptive_laguerre.core._numba_kernel import _rolling_percentile_numba


def _pandas_rolling_percentile(values: np.ndarray, window: int) -> np.ndarray:
    """Reference implementation — the original pandas lambda."""
    return (
        pd.Series(values)
        .rolling(window=window, min_periods=1)
        .apply(lambda x: (x[-1] > x[:-1]).sum() / len(x) * 100, raw=True)
        .fillna(50.0)
        .values
    )


class TestPercentileOracle:
    """Numba percentile must be bit-for-bit identical to pandas lambda."""

    @pytest.mark.parametrize("n_bars", [10, 100, 600, 2000])
    @pytest.mark.parametrize("window", [5, 20, 50])
    def test_random_data_exact(self, n_bars: int, window: int) -> None:
        np.random.seed(42)
        rsi = np.random.rand(n_bars)
        expected = _pandas_rolling_percentile(rsi, window)
        actual = _rolling_percentile_numba(rsi, window)
        np.testing.assert_array_equal(actual, expected)

    def test_flat_values(self) -> None:
        rsi = np.full(100, 0.5)
        expected = _pandas_rolling_percentile(rsi, 20)
        actual = _rolling_percentile_numba(rsi, 20)
        np.testing.assert_array_equal(actual, expected)

    def test_monotonic_increasing(self) -> None:
        rsi = np.linspace(0, 1, 200)
        expected = _pandas_rolling_percentile(rsi, 20)
        actual = _rolling_percentile_numba(rsi, 20)
        np.testing.assert_array_equal(actual, expected)

    def test_monotonic_decreasing(self) -> None:
        rsi = np.linspace(1, 0, 200)
        expected = _pandas_rolling_percentile(rsi, 20)
        actual = _rolling_percentile_numba(rsi, 20)
        np.testing.assert_array_equal(actual, expected)

    def test_single_bar(self) -> None:
        rsi = np.array([0.5])
        expected = _pandas_rolling_percentile(rsi, 20)
        actual = _rolling_percentile_numba(rsi, 20)
        np.testing.assert_array_equal(actual, expected)

    def test_window_larger_than_data(self) -> None:
        rsi = np.array([0.1, 0.5, 0.9, 0.3, 0.7])
        expected = _pandas_rolling_percentile(rsi, 50)
        actual = _rolling_percentile_numba(rsi, 50)
        np.testing.assert_array_equal(actual, expected)
