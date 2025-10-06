"""
Non-anticipative validation for feature constructors.

SLOs:
- Availability: 100% (pure computation, no external dependencies)
- Correctness: 100% (progressive subset validation method)
- Security: N/A (validation only)
- Observability: Full type hints (mypy strict)
- Maintainability: High (standard validation pattern)

Error Handling: raise_and_propagate
- ValueError on lookahead bias detection (feature violates non-anticipative property)
- TypeError on invalid input types (must propagate, not handle)
"""

from typing import Callable

import numpy as np
import pandas as pd


def validate_non_anticipative(
    feature_fn: Callable[[pd.DataFrame], pd.Series],
    df: pd.DataFrame,
    n_tests: int = 100,
    min_subset_ratio: float = 0.5,
) -> bool:
    """
    Validate feature function is non-anticipative via progressive computation.

    Test methodology:
    1. Compute feature on full dataset
    2. For n_tests progressively longer subsets:
       a. Compute feature on df[:length]
       b. Compare with full computation's overlapping values
    3. If overlapping values identical across all tests → non-anticipative
    4. If overlapping values differ → lookahead bias detected

    The key insight: if feature at bar i only uses data up to bar i-1,
    then adding bars i+1, i+2, ... should NOT change feature value at bar i.

    Args:
        feature_fn: Feature computation function (df → Series)
                   Must be deterministic: same input → same output
        df: Test DataFrame (OHLCV or other required columns)
           Must be sorted chronologically
        n_tests: Number of progressive subset tests (default: 100)
                 Tests n_tests equally-spaced subset lengths
        min_subset_ratio: Minimum subset length as ratio of full length (default: 0.5)
                         E.g., 0.5 means test subsets from 50% to 100% of df length

    Returns:
        True if feature is non-anticipative

    Raises:
        ValueError: If feature shows lookahead bias (past differs across subsets)
        TypeError: If inputs have invalid types (must propagate, not handle)

    Note:
        Compares with numpy.allclose(rtol=1e-9, atol=1e-12) for numerical stability.

    Example:
        >>> from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI
        >>> feature = ATRAdaptiveLaguerreRSI()
        >>> df = load_ohlcv_data()
        >>> is_valid = validate_non_anticipative(feature.fit_transform, df)
        >>> assert is_valid  # Feature is non-anticipative
    """
    # Validate input types
    if not callable(feature_fn):
        raise TypeError(f"feature_fn must be callable, got {type(feature_fn)}")

    if not isinstance(df, pd.DataFrame):
        raise TypeError(f"df must be pd.DataFrame, got {type(df)}")

    if not isinstance(n_tests, int) or n_tests <= 0:
        raise TypeError(f"n_tests must be positive int, got {n_tests}")

    if not isinstance(min_subset_ratio, (int, float)) or not 0 < min_subset_ratio <= 1.0:
        raise TypeError(
            f"min_subset_ratio must be float in (0, 1], got {min_subset_ratio}"
        )

    # Validate df has sufficient length
    if len(df) < 10:
        raise ValueError(f"df too short for validation (len={len(df)}, need >=10)")

    # Calculate minimum subset length
    min_length = max(int(len(df) * min_subset_ratio), 10)

    if len(df) < min_length:
        raise ValueError(
            f"df too short for validation (len={len(df)}, need >={min_length})"
        )

    # Compute baseline on full data (this may raise if feature_fn errors)
    full_feature = feature_fn(df)

    # Validate feature_fn returned pd.Series
    if not isinstance(full_feature, pd.Series):
        raise TypeError(
            f"feature_fn must return pd.Series, got {type(full_feature)}"
        )

    # Validate feature output length matches input
    if len(full_feature) != len(df):
        raise ValueError(
            f"feature_fn output length ({len(full_feature)}) "
            f"doesn't match input length ({len(df)})"
        )

    # Generate test subset lengths (evenly spaced from min to full)
    test_lengths = np.linspace(
        min_length, len(df), min(n_tests, len(df) - min_length + 1), dtype=int
    )
    test_lengths = np.unique(test_lengths)  # Remove duplicates

    # Test each progressive subset
    for test_len in test_lengths:
        # Compute feature on subset
        subset_df = df.iloc[:test_len]
        subset_feature = feature_fn(subset_df)

        # Validate subset feature output
        if not isinstance(subset_feature, pd.Series):
            raise TypeError(
                f"feature_fn must return pd.Series, got {type(subset_feature)}"
            )

        if len(subset_feature) != test_len:
            raise ValueError(
                f"feature_fn output length ({len(subset_feature)}) "
                f"doesn't match subset length ({test_len})"
            )

        # Extract overlapping portion from full computation
        full_overlap = full_feature.iloc[:test_len].values
        subset_values = subset_feature.values

        # Compare: overlap should be identical if non-anticipative
        if not np.allclose(full_overlap, subset_values, rtol=1e-9, atol=1e-12):
            max_diff = np.abs(full_overlap - subset_values).max()
            diff_idx = np.argmax(np.abs(full_overlap - subset_values))

            raise ValueError(
                f"Lookahead bias detected at subset length {test_len}!\n"
                f"Feature values changed when computed on subset vs full data.\n"
                f"Max diff: {max_diff:.2e} at index {diff_idx}\n"
                f"Full[{diff_idx}]={full_overlap[diff_idx]:.6f}, "
                f"Subset[{diff_idx}]={subset_values[diff_idx]:.6f}\n"
                f"This violates non-anticipative guarantee.\n"
                f"Feature computation at bar i must only use data from bars 0 to i-1."
            )

    # All tests passed → feature is non-anticipative
    return True
