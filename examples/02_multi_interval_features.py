"""
Example 2: Multi-Interval Feature Extraction (121 features).

This example demonstrates:
1. Configuring multi-interval feature extraction (3 intervals: base, 3×, 12×)
2. Extracting 81 single-interval features (27 per interval)
3. Extracting 40 cross-interval interaction features
4. Interpreting regime alignment across intervals

No external data dependencies - runs standalone.

Usage:
    uv run --with atr-adaptive-laguerre python examples/02_multi_interval_features.py
"""

import numpy as np
import pandas as pd

from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig


def generate_synthetic_ohlcv(n_bars: int = 600, seed: int = 42) -> pd.DataFrame:
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
    print("Example 2: Multi-Interval Feature Extraction (121 features)")
    print("=" * 80)

    # Step 1: Generate data
    print("\n[1/4] Generating synthetic OHLCV data (600 bars @ 5min = 50 hours)...")
    df = generate_synthetic_ohlcv(n_bars=600)
    print(f"  ✓ Generated {len(df)} bars from {df['date'].iloc[0]} to {df['date'].iloc[-1]}")

    # Step 2: Configure multi-interval extraction
    print("\n[2/4] Configuring multi-interval feature extraction...")
    print("  Intervals:")
    print("    • Base: 5min (provided data)")
    print("    • Mult1 (3×): 15min (3 × 5min)")
    print("    • Mult2 (12×): 60min (12 × 5min)")

    config = ATRAdaptiveLaguerreRSIConfig(
        atr_period=32,
        smoothing_period=5,
        level_up=0.85,
        level_down=0.15,
        multiplier_1=3,    # 3× base = 15min
        multiplier_2=12,   # 12× base = 60min
    )
    feature = ATRAdaptiveLaguerreRSI(config)

    # Step 3: Extract 121 features
    print("\n[3/4] Extracting 121 features (27×3 intervals + 40 interactions)...")
    features = feature.fit_transform_features(df)
    print(f"  ✓ Generated {features.shape[1]} features × {features.shape[0]} bars")

    # Verify feature counts
    base_cols = [c for c in features.columns if c.endswith("_base")]
    mult1_cols = [c for c in features.columns if c.endswith("_mult1")]
    mult2_cols = [c for c in features.columns if c.endswith("_mult2")]
    interaction_cols = [c for c in features.columns if not (c.endswith("_base") or c.endswith("_mult1") or c.endswith("_mult2"))]

    print(f"\n  Feature Breakdown:")
    print(f"    • Base interval (5min): {len(base_cols)} features")
    print(f"    • Mult1 interval (15min): {len(mult1_cols)} features")
    print(f"    • Mult2 interval (60min): {len(mult2_cols)} features")
    print(f"    • Cross-interval interactions: {len(interaction_cols)} features")
    print(f"    • Total: {len(base_cols) + len(mult1_cols) + len(mult2_cols) + len(interaction_cols)} features")

    # Step 4: Interpret cross-interval features
    print("\n[4/4] Interpreting cross-interval interactions...")

    # Extract a sample bar for analysis
    sample_idx = 300

    print(f"\n  Sample Bar #{sample_idx} ({df.loc[sample_idx, 'date']}):")
    print(f"    Base RSI (5min):  {features.loc[sample_idx, 'rsi_base']:.4f}")
    print(f"    Mult1 RSI (15min): {features.loc[sample_idx, 'rsi_mult1']:.4f}")
    print(f"    Mult2 RSI (60min): {features.loc[sample_idx, 'rsi_mult2']:.4f}")

    # Regime alignment
    regime_base = features.loc[sample_idx, 'regime_base']
    regime_mult1 = features.loc[sample_idx, 'regime_mult1']
    regime_mult2 = features.loc[sample_idx, 'regime_mult2']

    regime_names = {0: "Bearish", 1: "Neutral", 2: "Bullish"}
    print(f"\n  Regime Classification:")
    print(f"    Base (5min):  {regime_names[regime_base]} ({regime_base})")
    print(f"    Mult1 (15min): {regime_names[regime_mult1]} ({regime_mult1})")
    print(f"    Mult2 (60min): {regime_names[regime_mult2]} ({regime_mult2})")

    # Cross-interval interactions
    print(f"\n  Cross-Interval Interactions:")
    print(f"    All intervals bullish: {features.loc[sample_idx, 'all_intervals_bullish']}")
    print(f"    All intervals bearish: {features.loc[sample_idx, 'all_intervals_bearish']}")
    print(f"    Regime unanimity: {features.loc[sample_idx, 'regime_unanimity']}")
    print(f"    Regime agreement count: {features.loc[sample_idx, 'regime_agreement_count']}/3")
    print(f"    Divergence strength: {features.loc[sample_idx, 'divergence_strength']:.4f}")
    print(f"    Momentum consistency: {features.loc[sample_idx, 'momentum_consistency']}")

    # Display regime distribution across intervals
    print("\n[Regime Distribution Across Intervals]")
    for interval, suffix in [("Base (5min)", "_base"), ("Mult1 (15min)", "_mult1"), ("Mult2 (60min)", "_mult2")]:
        regime_col = f"regime{suffix}"
        bearish_pct = (features[regime_col] == 0).sum() / len(features) * 100
        neutral_pct = (features[regime_col] == 1).sum() / len(features) * 100
        bullish_pct = (features[regime_col] == 2).sum() / len(features) * 100

        print(f"  {interval}:")
        print(f"    Bearish: {bearish_pct:.1f}% | Neutral: {neutral_pct:.1f}% | Bullish: {bullish_pct:.1f}%")

    # Cross-interval alignment statistics
    print("\n[Cross-Interval Alignment Statistics]")
    unanimity_pct = (features['regime_unanimity'] == 1).sum() / len(features) * 100
    all_bullish_pct = (features['all_intervals_bullish'] == 1).sum() / len(features) * 100
    all_bearish_pct = (features['all_intervals_bearish'] == 1).sum() / len(features) * 100

    print(f"  Unanimity (all 3 agree): {unanimity_pct:.1f}% of bars")
    print(f"  All bullish: {all_bullish_pct:.1f}% of bars")
    print(f"  All bearish: {all_bearish_pct:.1f}% of bars")

    # Display sample output
    print("\n[Sample Output] Selected Columns (first 5 rows):")
    pd.set_option('display.max_columns', 15)
    pd.set_option('display.width', 150)
    sample_cols = ['rsi_base', 'rsi_mult1', 'rsi_mult2', 'regime_base', 'regime_mult1', 'regime_mult2',
                   'regime_unanimity', 'divergence_strength', 'momentum_consistency']
    print(features[sample_cols].head())

    print("\n" + "=" * 80)
    print("✓ Example completed successfully!")
    print("  Tip: Use these 121 features as inputs to seq2seq models (LSTM, Transformer)")
    print("=" * 80)


if __name__ == "__main__":
    main()
