"""
Example 3: Walk-Forward Backtest with Train/Test Separation.

This example demonstrates:
1. Proper train/test split (temporal, no overlap)
2. Feature extraction on each window independently
3. Validation of non-anticipative guarantee
4. Information Coefficient (IC) calculation on test set

Validates strict train/test separation rules:
- Train on past; infer on future—never reuse training rows
- No cross-window peeking
- Stateless feature extraction per window

Usage:
    uv run --with atr-adaptive-laguerre python examples/03_walk_forward_backtest.py
"""

import numpy as np
import pandas as pd

from atr_adaptive_laguerre import (
    ATRAdaptiveLaguerreRSI,
    ATRAdaptiveLaguerreRSIConfig,
    calculate_information_coefficient,
)


def generate_synthetic_ohlcv(n_bars: int = 1000, seed: int = 42) -> pd.DataFrame:
    """Generate synthetic OHLCV data with predictable patterns."""
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
    print("Example 3: Walk-Forward Backtest with Train/Test Separation")
    print("=" * 80)

    # Step 1: Generate data
    print("\n[1/6] Generating synthetic OHLCV data (1000 bars)...")
    df = generate_synthetic_ohlcv(n_bars=1000)
    print(f"  ✓ Generated {len(df)} bars from {df['date'].iloc[0]} to {df['date'].iloc[-1]}")

    # Step 2: Define train/test split
    print("\n[2/6] Defining train/test split (60% train / 40% test)...")
    train_end = 600
    train_df = df.iloc[:train_end]
    test_df = df.iloc[train_end:]

    print(f"  Train window:")
    print(f"    Bars: 0-{train_end - 1} ({len(train_df)} bars)")
    print(f"    Dates: {train_df['date'].iloc[0]} → {train_df['date'].iloc[-1]}")
    print(f"  Test window:")
    print(f"    Bars: {train_end}-{len(df) - 1} ({len(test_df)} bars)")
    print(f"    Dates: {test_df['date'].iloc[0]} → {test_df['date'].iloc[-1]}")

    # Verify no overlap
    overlap = set(train_df.index).intersection(set(test_df.index))
    print(f"  ✓ Index overlap: {len(overlap)} (MUST be 0 for valid backtest)")

    # Step 3: Extract features on training window
    print("\n[3/6] Extracting features on training window...")
    config = ATRAdaptiveLaguerreRSIConfig(
        atr_period=32,
        smoothing_period=5,
        multiplier_1=3,
        multiplier_2=12,
    )
    feature = ATRAdaptiveLaguerreRSI(config)

    features_train = feature.fit_transform_features(train_df)
    print(f"  ✓ Train features: {features_train.shape[1]} columns × {features_train.shape[0]} rows")

    # Step 4: Extract features on test window
    print("\n[4/6] Extracting features on test window...")
    features_test = feature.fit_transform_features(test_df)
    print(f"  ✓ Test features: {features_test.shape[1]} columns × {features_test.shape[0]} rows")

    # Critical validation: Indices must not overlap
    overlap_features = set(features_train.index).intersection(set(features_test.index))
    print(f"  ✓ Feature index overlap: {len(overlap_features)} (MUST be 0)")

    if len(overlap_features) > 0:
        print("  ✗ CRITICAL ERROR: Train and test features overlap!")
        print("    This violates temporal separation and will cause data leakage.")
        return

    # Step 5: Validate non-anticipative guarantee
    print("\n[5/6] Validating non-anticipative guarantee...")
    print("  Testing: Adding future data should NOT change past features")

    # Compute features on full data
    features_full = feature.fit_transform_features(df)

    # Compare training portion
    base_cols = [c for c in features_train.columns if c.endswith("_base")]
    all_match = True

    for col in base_cols:
        train_vals = features_train[col].values
        full_vals = features_full.loc[:train_end - 1, col].values

        if not np.allclose(train_vals, full_vals, rtol=1e-9, atol=1e-12):
            print(f"  ✗ FAILED: Column '{col}' changed when full data added")
            all_match = False
            break

    if all_match:
        print(f"  ✓ Validated {len(base_cols)} base features: IDENTICAL on train window")
        print("    (Adding test data did NOT change training features)")
    else:
        print("  ✗ Non-anticipative guarantee VIOLATED")
        return

    # Step 6: Calculate Information Coefficient on test set
    print("\n[6/6] Calculating Information Coefficient on test set...")
    print("  IC = Spearman correlation(feature[t], forward_return[t+k])")

    # Calculate forward returns for test set
    test_prices = test_df["close"].reset_index(drop=True)
    forward_periods = 5  # Predict 5 bars ahead

    # Use base RSI as example feature
    test_rsi = features_test["rsi_base"].reset_index(drop=True)

    # Calculate IC
    ic_result = calculate_information_coefficient(
        feature_series=test_rsi,
        prices=test_prices,
        forward_periods=forward_periods,
    )

    print(f"\n  Results:")
    print(f"    Feature: rsi_base (5-bar forward return)")
    print(f"    IC: {ic_result['ic']:.4f}")
    print(f"    Valid samples: {ic_result['n_valid']}/{len(test_rsi)}")

    # Interpret IC
    if abs(ic_result['ic']) > 0.03:
        print(f"  ✓ IC > 0.03: Feature has PREDICTIVE POWER")
    elif abs(ic_result['ic']) > 0.01:
        print(f"  ⚠ IC ≈ 0.01-0.03: Weak predictive signal")
    else:
        print(f"  ℹ IC ≈ 0: No predictive power (expected for random data)")

    # Additional validation metrics
    print("\n[Additional Metrics]")

    # Feature stability across train/test
    train_rsi_mean = features_train["rsi_base"].mean()
    test_rsi_mean = features_test["rsi_base"].mean()
    print(f"  RSI mean (train): {train_rsi_mean:.4f}")
    print(f"  RSI mean (test):  {test_rsi_mean:.4f}")
    print(f"  Distribution shift: {abs(train_rsi_mean - test_rsi_mean):.4f}")

    # Regime distribution
    print(f"\n  Regime distribution (test set):")
    regime_counts = features_test["regime_base"].value_counts().sort_index()
    regime_names = {0: "Bearish", 1: "Neutral", 2: "Bullish"}
    for regime, count in regime_counts.items():
        pct = count / len(features_test) * 100
        print(f"    {regime_names[regime]} ({regime}): {pct:.1f}% ({count} bars)")

    print("\n" + "=" * 80)
    print("✓ Walk-forward backtest completed successfully!")
    print("\nKey Takeaways:")
    print("  1. Train and test windows are fully isolated (no data leakage)")
    print("  2. Features are non-anticipative (adding future data doesn't change past)")
    print("  3. IC measured ONLY on test set (unbiased performance estimate)")
    print("  4. Template ready for production backtesting workflows")
    print("=" * 80)


if __name__ == "__main__":
    main()
