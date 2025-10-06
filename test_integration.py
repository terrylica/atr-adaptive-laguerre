"""
Quick integration test for ATR-Adaptive Laguerre RSI feature.

Validates:
1. Feature can be instantiated
2. fit_transform() works on synthetic OHLCV data
3. Output has expected shape and range (0.0 to 1.0)
4. Non-anticipative validation passes
"""

import numpy as np
import pandas as pd

from atr_adaptive_laguerre import (
    ATRAdaptiveLaguerreRSI,
    ATRAdaptiveLaguerreRSIConfig,
)


def generate_synthetic_ohlcv(n_bars: int = 100) -> pd.DataFrame:
    """Generate synthetic OHLCV data for testing."""
    dates = pd.date_range("2024-01-01", periods=n_bars, freq="1h")

    # Generate random walk close prices
    np.random.seed(42)
    close = 100 + np.cumsum(np.random.randn(n_bars) * 0.5)

    # Generate OHLC with realistic constraints
    high = close + np.abs(np.random.randn(n_bars) * 0.3)
    low = close - np.abs(np.random.randn(n_bars) * 0.3)
    open_price = close + np.random.randn(n_bars) * 0.2
    volume = np.abs(np.random.randn(n_bars) * 1000 + 5000)

    return pd.DataFrame({
        "date": dates,
        "open": open_price,
        "high": high,
        "low": low,
        "close": close,
        "volume": volume,
    })


def main():
    """Run integration test."""
    print("🔬 ATR-Adaptive Laguerre RSI Integration Test\n")

    # Test 1: Feature instantiation
    print("Test 1: Feature instantiation...")
    config = ATRAdaptiveLaguerreRSIConfig(
        atr_period=32,
        smoothing_period=5,
        level_up=0.85,
        level_down=0.15,
    )
    feature = ATRAdaptiveLaguerreRSI(config)
    print("✅ Feature instantiated successfully\n")

    # Test 2: fit_transform on synthetic data
    print("Test 2: fit_transform() on 100-bar synthetic OHLCV...")
    df = generate_synthetic_ohlcv(n_bars=100)
    rsi_series = feature.fit_transform(df)
    print(f"✅ fit_transform() returned Series with shape {rsi_series.shape}\n")

    # Test 3: Validate output range
    print("Test 3: Validate output range (0.0 to 1.0)...")
    assert rsi_series.min() >= 0.0, f"RSI min {rsi_series.min()} < 0.0"
    assert rsi_series.max() <= 1.0, f"RSI max {rsi_series.max()} > 1.0"
    print(f"✅ RSI range: [{rsi_series.min():.4f}, {rsi_series.max():.4f}]\n")

    # Test 4: Non-anticipative validation
    print("Test 4: Non-anticipative validation (10 shuffles)...")
    is_non_anticipative = feature.validate_non_anticipative(df, n_shuffles=10)
    assert is_non_anticipative, "Non-anticipative validation failed"
    print("✅ Non-anticipative guarantee validated\n")

    # Test 5: Edge cases
    print("Test 5: Edge case - minimum data (10 bars)...")
    df_small = generate_synthetic_ohlcv(n_bars=10)
    rsi_small = feature.fit_transform(df_small)
    assert len(rsi_small) == 10, f"Expected 10 bars, got {len(rsi_small)}"
    print("✅ Minimum data edge case passed\n")

    # Summary
    print("=" * 60)
    print("✅ All Integration Tests Passed!")
    print("=" * 60)
    print("\nFeature Statistics:")
    print(f"  - Config: {config}")
    print(f"  - Test data shape: {df.shape}")
    print(f"  - RSI output shape: {rsi_series.shape}")
    print(f"  - RSI mean: {rsi_series.mean():.4f}")
    print(f"  - RSI std: {rsi_series.std():.4f}")
    print(f"  - Non-anticipative: ✅")


if __name__ == "__main__":
    main()
