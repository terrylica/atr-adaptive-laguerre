"""
Generate golden snapshot files for memory efficiency refactoring regression test.

Run this script ONCE before making any source code changes:
    python tests/test_features/generate_golden_snapshots.py

Produces 6 .npy files in tests/fixtures/ with exact binary float64 values.
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd

# Ensure the package is importable
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig

FIXTURES_DIR = Path(__file__).resolve().parents[1] / "fixtures"


def generate_ohlcv(n_bars: int = 600) -> pd.DataFrame:
    """Same seed/shape as test_feature_expander.py sample_ohlcv fixture."""
    np.random.seed(42)
    base_price = 100 + np.cumsum(np.random.randn(n_bars) * 0.5)
    close = base_price
    open_ = close + np.random.randn(n_bars) * 0.3
    high = np.maximum(close, open_) + np.abs(np.random.randn(n_bars) * 0.2)
    low = np.minimum(close, open_) - np.abs(np.random.randn(n_bars) * 0.2)
    volume = np.random.randint(1000, 10000, n_bars)
    dates = pd.date_range("2024-01-01", periods=n_bars, freq="5min")
    return pd.DataFrame(
        {"date": dates, "open": open_, "high": high, "low": low, "close": close, "volume": volume}
    )


def main() -> None:
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    ohlcv = generate_ohlcv()

    # 1. Single-interval (43 features)
    config_single = ATRAdaptiveLaguerreRSIConfig.single_interval()
    indicator_single = ATRAdaptiveLaguerreRSI(config_single)
    features_43 = indicator_single.fit_transform_features(ohlcv)
    assert features_43.shape == (600, 43), f"Expected (600, 43), got {features_43.shape}"
    np.save(FIXTURES_DIR / "golden_single_43.npy", features_43.values)
    np.save(FIXTURES_DIR / "golden_columns_43.npy", np.array(features_43.columns.tolist()))
    print(f"Saved golden_single_43.npy: {features_43.shape}")

    # 2. Multi-interval unfiltered (169 features)
    config_multi = ATRAdaptiveLaguerreRSIConfig.multi_interval(
        multiplier_1=3, multiplier_2=12, filter_redundancy=False
    )
    indicator_multi = ATRAdaptiveLaguerreRSI(config_multi)
    features_169 = indicator_multi.fit_transform_features(ohlcv)
    assert features_169.shape == (600, 169), f"Expected (600, 169), got {features_169.shape}"
    np.save(FIXTURES_DIR / "golden_multi_169.npy", features_169.values)
    np.save(FIXTURES_DIR / "golden_columns_169.npy", np.array(features_169.columns.tolist()))
    print(f"Saved golden_multi_169.npy: {features_169.shape}")

    # 3. Multi-interval filtered (121 features)
    config_filtered = ATRAdaptiveLaguerreRSIConfig.multi_interval(
        multiplier_1=3, multiplier_2=12, filter_redundancy=True
    )
    indicator_filtered = ATRAdaptiveLaguerreRSI(config_filtered)
    features_121 = indicator_filtered.fit_transform_features(ohlcv)
    assert features_121.shape == (600, 121), f"Expected (600, 121), got {features_121.shape}"
    np.save(FIXTURES_DIR / "golden_multi_121.npy", features_121.values)
    np.save(FIXTURES_DIR / "golden_columns_121.npy", np.array(features_121.columns.tolist()))
    print(f"Saved golden_multi_121.npy: {features_121.shape}")

    print(f"\nAll golden snapshots saved to {FIXTURES_DIR}")


if __name__ == "__main__":
    main()
