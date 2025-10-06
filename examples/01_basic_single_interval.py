"""
Example 1: Basic Single-Interval Feature Extraction (27 features).

This example demonstrates:
1. Creating synthetic OHLCV data
2. Extracting base RSI (1 column)
3. Expanding to 27 single-interval features
4. Validating non-anticipative guarantee

No external data dependencies - runs standalone.

Usage:
    uv run --with atr-adaptive-laguerre python examples/01_basic_single_interval.py
"""

import numpy as np
import pandas as pd

from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig


def generate_synthetic_ohlcv(n_bars: int = 500, seed: int = 42) -> pd.DataFrame:
    """Generate synthetic OHLCV data for demonstration."""
    np.random.seed(seed)

    # Generate realistic price movement
    base_price = 100 + np.cumsum(np.random.randn(n_bars) * 0.5)

    # Create OHLC with proper relationships
    close = base_price
    open_ = close + np.random.randn(n_bars) * 0.3
    high = np.maximum(close, open_) + np.abs(np.random.randn(n_bars) * 0.2)
    low = np.minimum(close, open_) - np.abs(np.random.randn(n_bars) * 0.2)
    volume = np.random.randint(1000, 10000, n_bars)

    dates = pd.date_range("2024-01-01", periods=n_bars, freq="5min")

    return pd.DataFrame({
        "date": dates,
        "open": open_,
        "high": high,
        "low": low,
        "close": close,
        "volume": volume,
    })


def main():
    """Main example execution."""
    print("=" * 80)
    print("Example 1: Basic Single-Interval Feature Extraction (27 features)")
    print("=" * 80)

    # Step 1: Generate data
    print("\n[1/4] Generating synthetic OHLCV data (500 bars)...")
    df = generate_synthetic_ohlcv(n_bars=500)
    print(f"  ✓ Generated {len(df)} bars from {df['date'].iloc[0]} to {df['date'].iloc[-1]}")

    # Step 2: Extract base RSI
    print("\n[2/4] Extracting base ATR-Adaptive Laguerre RSI...")
    config = ATRAdaptiveLaguerreRSIConfig(
        atr_period=32,
        smoothing_period=5,
        level_up=0.85,
        level_down=0.15,
    )
    feature = ATRAdaptiveLaguerreRSI(config)
    rsi = feature.fit_transform(df)
    print(f"  ✓ Extracted RSI: shape={rsi.shape}, range=[{rsi.min():.4f}, {rsi.max():.4f}]")

    # Step 3: Expand to 27 features
    print("\n[3/4] Expanding to 27 single-interval features...")
    features = feature.fit_transform_features(df)
    print(f"  ✓ Generated {features.shape[1]} features × {features.shape[0]} bars")

    # Display feature categories
    print("\n  Feature Categories:")
    categories = {
        "Base Indicator": ["rsi"],
        "Regimes (7)": [c for c in features.columns if c.startswith("regime")],
        "Thresholds (5)": [c for c in features.columns if "dist_" in c or "abs_dist" in c],
        "Crossings (4)": [c for c in features.columns if "cross_" in c],
        "Temporal (3)": [c for c in features.columns if "bars_since" in c],
        "Rate of Change (3)": [c for c in features.columns if "rsi_change" in c or "velocity" in c],
        "Statistics (4)": [c for c in features.columns if "percentile" in c or "zscore" in c or "volatility" in c or "range_20" in c],
    }

    for cat_name, cols in categories.items():
        print(f"    • {cat_name}: {len(cols)} features")

    # Step 4: Validate non-anticipative guarantee
    print("\n[4/4] Validating non-anticipative guarantee...")
    print("  Testing via progressive subset validation...")

    test_lengths = [
        int(len(df) * 0.75),
        int(len(df) * 0.9),
        len(df),
    ]

    all_passed = True
    for test_len in test_lengths[:-1]:  # Skip full length (trivial)
        features_subset = feature.fit_transform_features(df.iloc[:test_len])

        # Compare overlapping portion
        for col in features.columns:
            full_vals = features.loc[:test_len - 1, col].values
            subset_vals = features_subset[col].values

            if not np.allclose(full_vals, subset_vals, rtol=1e-9, atol=1e-12):
                print(f"    ✗ FAILED at length {test_len} for column {col}")
                all_passed = False
                break

        if all_passed:
            print(f"    ✓ Subset {test_len}/{len(df)} bars: PASSED")

    if all_passed:
        print("\n  ✓ Non-anticipative guarantee: VALIDATED")
        print("    (Adding future data does NOT change past features)")
    else:
        print("\n  ✗ Non-anticipative guarantee: FAILED")

    # Display sample features
    print("\n[Sample Output] First 5 rows:")
    pd.set_option('display.max_columns', 10)
    pd.set_option('display.width', 120)
    print(features.head())

    # Feature statistics
    print("\n[Feature Statistics]")
    print(f"  RSI mean: {features['rsi'].mean():.4f}")
    print(f"  Regime distribution:")
    print(f"    Bearish (0): {(features['regime'] == 0).sum()} bars ({(features['regime'] == 0).sum() / len(features) * 100:.1f}%)")
    print(f"    Neutral (1): {(features['regime'] == 1).sum()} bars ({(features['regime'] == 1).sum() / len(features) * 100:.1f}%)")
    print(f"    Bullish (2): {(features['regime'] == 2).sum()} bars ({(features['regime'] == 2).sum() / len(features) * 100:.1f}%)")

    print("\n" + "=" * 80)
    print("✓ Example completed successfully!")
    print("=" * 80)


if __name__ == "__main__":
    main()
