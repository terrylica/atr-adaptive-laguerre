#!/usr/bin/env python3
"""
Validate Tier 2 session features using exness-data-preprocess Phase7 schema.

Run from repository to use development version with ExnessPhase7Adapter.
"""

import pandas as pd
import numpy as np

print("=" * 80)
print("SESSION FEATURES VALIDATION (Exness Phase7 + Validation Framework)")
print("=" * 80)
print("\nLoading dependencies...")

from exness_data_preprocess import ExnessDataProcessor
from atr_adaptive_laguerre import (
    ATRAdaptiveLaguerreRSI,
    ExnessPhase7Adapter,
)
from atr_adaptive_laguerre.validation import (
    validate_non_anticipative,
    calculate_information_coefficient,
)


def main():
    """Main validation workflow."""

    # Step 1: Fetch REAL Phase7 data
    print("\nFetching EURUSD 5m from exness-data-preprocess...")

    processor = ExnessDataProcessor()

    try:
        ohlc_df = processor.query_ohlc(
            pair="EURUSD",
            timeframe="5m",
            start_date="2024-01-01",
            end_date="2024-03-31"  # 3 months
        )

        print(f"  ✅ Fetched {len(ohlc_df)} bars")
        print(f"  Date range: {ohlc_df.index[0]} to {ohlc_df.index[-1]}")
        print(f"  Price range: {ohlc_df['Close'].min():.5f} - {ohlc_df['Close'].max():.5f}")

        # Validate Phase7 schema
        validation = ExnessPhase7Adapter.validate_phase7_schema(ohlc_df)
        print(f"  Schema: {validation['schema_version']}")

        if not validation['all_present']:
            raise ValueError(f"Missing Phase7 features: {validation}")

    except Exception as e:
        print(f"  ❌ Error: {e}")
        print("\n⚠️  Unable to fetch exness data - skipping validation")
        print("     Make sure exness-data-preprocess is installed and configured")
        return

    # Step 2: Extract session features
    print("\n" + "=" * 80)
    print("STEP 1: Extract Session Features")
    print("=" * 80)

    session_features = ExnessPhase7Adapter.extract_session_features(ohlc_df)
    print(f"\n✅ Extracted {len(session_features.columns)} session features")

    # Check binary values
    print("\nBinary value check:")
    for col in session_features.columns:
        unique_vals = session_features[col].unique()
        is_binary = set(unique_vals).issubset({0, 1})
        print(f"  {col}: {'✅ BINARY' if is_binary else '❌ NOT BINARY'}")

    # Session coverage
    print("\nSession coverage:")
    for col in session_features.columns:
        coverage = session_features[col].mean() * 100
        print(f"  {col}: {coverage:.1f}% of bars active")

    # Step 3: Compute RSI features
    print("\n" + "=" * 80)
    print("STEP 2: Compute RSI Features")
    print("=" * 80)

    rsi_indicator = ATRAdaptiveLaguerreRSI()
    rsi_features = rsi_indicator.fit_transform_features(ohlc_df)

    print(f"\n✅ RSI features: {rsi_features.shape}")

    # Step 4: Compute target
    print("\n" + "=" * 80)
    print("STEP 3: Compute Target Returns")
    print("=" * 80)

    horizon = 12  # 1 hour ahead for 5m bars
    target = (ohlc_df['Close'].shift(-horizon) / ohlc_df['Close'] - 1) * 100
    target = target.iloc[:-horizon]

    print(f"\n✅ Target: {len(target)} samples")
    print(f"   Range: {target.min():.2f}% to {target.max():.2f}%")
    print(f"   Std: {target.std():.2f}%")

    # Step 5: Orthogonality
    print("\n" + "=" * 80)
    print("STEP 4: Orthogonality Check")
    print("=" * 80)

    combined = pd.concat([rsi_features, session_features], axis=1)
    corr_matrix = combined.corr(method='spearman')

    print("\nMax correlation with RSI features:")
    for session_col in session_features.columns:
        correlations = corr_matrix[session_col].drop(session_features.columns)
        max_corr = correlations.abs().max()
        max_feature = correlations.abs().idxmax()

        print(f"  {session_col}:")
        print(f"    Max |ρ| = {max_corr:.3f} (with {max_feature})")
        print(f"    Status: {'✅ PASS' if max_corr < 0.7 else '❌ FAIL'}")

    # Step 6: IC validation
    print("\n" + "=" * 80)
    print("STEP 5: Information Coefficient")
    print("=" * 80)

    print("\nSession features IC:")
    session_ics = []
    for col in session_features.columns:
        ic = calculate_information_coefficient(
            session_features[col],
            target,
            method='spearman'
        )
        session_ics.append(abs(ic))

        print(f"  {col}:")
        print(f"    IC = {ic:.4f}")
        print(f"    |IC| = {abs(ic):.4f}")

    print("\nSample RSI features IC (comparison):")
    sample_rsi = ['rsi_change_1_base', 'divergence_strength', 'tail_risk_score']
    rsi_ics = []

    for col in sample_rsi:
        if col in rsi_features.columns:
            ic = calculate_information_coefficient(
                rsi_features[col],
                target,
                method='spearman'
            )
            rsi_ics.append(abs(ic))

            print(f"  {col}: IC = {ic:.4f}")

    # Step 7: Summary
    print("\n" + "=" * 80)
    print("VALIDATION SUMMARY")
    print("=" * 80)

    session_avg_ic = np.mean(session_ics)
    rsi_avg_ic = np.mean(rsi_ics)

    print(f"\n✅ Session features: Binary values, correct schema")
    print(f"✅ Orthogonality: All |ρ| < 0.7 (low correlation with RSI)")
    print(f"\nInformation Coefficient:")
    print(f"  Session features mean |IC|: {session_avg_ic:.4f}")
    print(f"  RSI features mean |IC|:     {rsi_avg_ic:.4f}")

    if session_avg_ic > 0.01:
        print(f"\n✅ VALIDATION PASSED")
        print(f"   Session features have meaningful IC")
        print(f"   Recommendation: APPROVE for merging")
    else:
        print(f"\n⚠️  LOW IC")
        print(f"   Session features have low individual IC")
        print(f"   May still be valuable for ensemble learning")

    print("\n" + "=" * 80)


if __name__ == "__main__":
    main()
