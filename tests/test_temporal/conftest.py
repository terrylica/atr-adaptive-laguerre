"""
Fixtures for temporal leakage testing.

SLOs:
- Correctness: 100% - Fixtures generate valid test data
- Observability: 100% - Clear error messages on fixture failures
- Maintainability: 90% - Reusable across all temporal tests

Error Handling: raise_and_propagate
- All fixture failures propagate with full context
- No defaults, fallbacks, or retries
"""

from datetime import datetime, timedelta, timezone
from typing import Literal

import numpy as np
import pandas as pd
import pytest

from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig


@pytest.fixture
def synthetic_ohlcv_data():
    """
    Generate synthetic OHLCV data with availability column.

    Returns function that accepts parameters for customization.

    Raises:
        ValueError: If invalid parameters provided
    """

    def _generate(
        n_bars: int = 500,
        base_interval_hours: int = 2,
        start_time: datetime | None = None,
        availability_delay_hours: int = 2,
        price_seed: int = 42,
    ) -> pd.DataFrame:
        """
        Generate synthetic OHLCV data.

        Args:
            n_bars: Number of bars to generate
            base_interval_hours: Hours between bars
            start_time: Start timestamp (default: 2024-01-01 00:00 UTC)
            availability_delay_hours: Hours delay for availability
            price_seed: Random seed for price generation

        Returns:
            DataFrame with columns: date, open, high, low, close, volume, actual_ready_time

        Raises:
            ValueError: If n_bars < 1 or intervals invalid
        """
        if n_bars < 1:
            raise ValueError(f"n_bars must be >= 1, got {n_bars}")
        if base_interval_hours < 1:
            raise ValueError(
                f"base_interval_hours must be >= 1, got {base_interval_hours}"
            )
        if availability_delay_hours < 0:
            raise ValueError(
                f"availability_delay_hours must be >= 0, got {availability_delay_hours}"
            )

        if start_time is None:
            start_time = datetime(2024, 1, 1, 0, 0, tzinfo=timezone.utc)

        # Generate timestamps
        dates = [
            start_time + timedelta(hours=base_interval_hours * i) for i in range(n_bars)
        ]

        # Generate realistic price movement
        np.random.seed(price_seed)
        price_base = 50000
        trend = np.linspace(0, 10000, n_bars)
        volatility = np.random.normal(0, 500, n_bars).cumsum()
        noise = np.random.normal(0, 100, n_bars)
        close_prices = price_base + trend + volatility + noise

        # Generate OHLCV
        data = pd.DataFrame(
            {
                "date": dates,
                "open": close_prices * 0.999,
                "high": close_prices * 1.002,
                "low": close_prices * 0.998,
                "close": close_prices,
                "volume": np.random.uniform(1000000, 5000000, n_bars),
                "actual_ready_time": [
                    d + timedelta(hours=availability_delay_hours) for d in dates
                ],
            }
        )

        return data

    return _generate


@pytest.fixture
def multi_interval_config():
    """
    Create standard multi-interval configuration.

    Returns function that accepts parameters for customization.

    Raises:
        ValueError: If multipliers invalid
    """

    def _create(
        multiplier_1: int = 4,
        multiplier_2: int = 12,
        filter_redundancy: bool = False,
        availability_column: str | None = "actual_ready_time",
    ) -> ATRAdaptiveLaguerreRSIConfig:
        """
        Create multi-interval config.

        Args:
            multiplier_1: First multiplier (default: 4)
            multiplier_2: Second multiplier (default: 12)
            filter_redundancy: Enable redundancy filtering
            availability_column: Availability column name

        Returns:
            ATRAdaptiveLaguerreRSIConfig configured for multi-interval mode

        Raises:
            ValueError: If multipliers invalid (propagated from config)
        """
        return ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=multiplier_1,
            multiplier_2=multiplier_2,
            filter_redundancy=filter_redundancy,
            availability_column=availability_column,
        )

    return _create


@pytest.fixture
def temporal_validator():
    """
    Validate temporal non-leakage property.

    Returns function that validates features don't leak.

    Raises:
        AssertionError: If temporal leakage detected
    """

    def _validate(
        data: pd.DataFrame,
        indicator: ATRAdaptiveLaguerreRSI,
        validation_idx: int,
        tolerance: float = 1e-10,
        features_to_check: list[str] | None = None,
    ) -> dict:
        """
        Validate no temporal leakage at validation_idx.

        Args:
            data: Full dataset with availability column
            indicator: Configured indicator instance
            validation_idx: Index to validate
            tolerance: Numerical tolerance for comparison
            features_to_check: List of feature names (default: ['rsi', 'rsi_mult1', 'rsi_mult2'])

        Returns:
            Dict with validation results:
                - passed: bool
                - failures: list of dicts with failure details

        Raises:
            ValueError: If validation_idx out of bounds
            AssertionError: If temporal leakage detected
        """
        if validation_idx < 0 or validation_idx >= len(data):
            raise ValueError(
                f"validation_idx {validation_idx} out of bounds for data length {len(data)}"
            )

        avail_col = indicator.config.availability_column
        if avail_col is None:
            raise ValueError("availability_column must be set for temporal validation")

        # Compute features on full dataset (ground truth)
        features_full = indicator.fit_transform_features(data)

        # Compute features on filtered dataset (prediction scenario)
        validation_time = data.iloc[validation_idx][avail_col]
        pred_data = data[data[avail_col] <= validation_time].copy()

        if len(pred_data) < indicator.min_lookback:
            raise ValueError(
                f"Insufficient data at validation_idx {validation_idx}: "
                f"{len(pred_data)} < {indicator.min_lookback} required"
            )

        features_pred = indicator.fit_transform_features(pred_data)

        # Compare features
        if features_to_check is None:
            features_to_check = ["rsi", "rsi_mult1", "rsi_mult2"]

        failures = []
        for feature in features_to_check:
            if feature not in features_pred.columns or feature not in features_full.columns:
                continue

            pred_val = features_pred.iloc[-1][feature]
            full_val = features_full.iloc[validation_idx][feature]
            diff = abs(pred_val - full_val)

            if diff > tolerance:
                failures.append(
                    {
                        "feature": feature,
                        "validation_idx": validation_idx,
                        "validation_time": validation_time,
                        "predicted_value": pred_val,
                        "ground_truth_value": full_val,
                        "difference": diff,
                        "tolerance": tolerance,
                    }
                )

        if failures:
            failure_msg = f"Temporal leakage detected at idx={validation_idx}:\n"
            for f in failures:
                failure_msg += (
                    f"  {f['feature']}: pred={f['predicted_value']:.10f} "
                    f"truth={f['ground_truth_value']:.10f} diff={f['difference']:.10e}\n"
                )
            raise AssertionError(failure_msg)

        return {"passed": True, "failures": failures}

    return _validate


@pytest.fixture
def boundary_timestamps():
    """
    Generate boundary timestamps for mult1 and mult2.

    Returns function that finds boundary alignment timestamps.

    Raises:
        ValueError: If invalid parameters
    """

    def _find(
        data: pd.DataFrame,
        multiplier_1: int,
        multiplier_2: int,
        base_interval_hours: int,
        boundary_type: Literal["mult1", "mult2", "both"],
    ) -> list[int]:
        """
        Find indices where timestamps align with resampled boundaries.

        Args:
            data: DataFrame with date column
            multiplier_1: First multiplier
            multiplier_2: Second multiplier
            base_interval_hours: Base interval in hours
            boundary_type: Which boundaries to find

        Returns:
            List of indices where boundaries align

        Raises:
            ValueError: If invalid boundary_type or missing data
        """
        if boundary_type not in ["mult1", "mult2", "both"]:
            raise ValueError(
                f"boundary_type must be 'mult1', 'mult2', or 'both', got {boundary_type}"
            )

        if "date" not in data.columns:
            raise ValueError("data must have 'date' column")

        start_time = data.iloc[0]["date"]
        indices = []

        for idx in range(len(data)):
            hours_from_start = (
                data.iloc[idx]["date"] - start_time
            ).total_seconds() / 3600

            if boundary_type == "mult1":
                if hours_from_start % (base_interval_hours * multiplier_1) == 0:
                    indices.append(idx)
            elif boundary_type == "mult2":
                if hours_from_start % (base_interval_hours * multiplier_2) == 0:
                    indices.append(idx)
            elif boundary_type == "both":
                lcm = np.lcm(multiplier_1, multiplier_2)
                if hours_from_start % (base_interval_hours * lcm) == 0:
                    indices.append(idx)

        return indices

    return _find
