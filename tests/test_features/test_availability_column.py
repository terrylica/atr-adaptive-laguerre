"""
Tests for availability_column parameter to prevent data leakage.

This module tests that multi-interval mode correctly respects temporal
availability constraints when availability_column is specified.
"""

import pandas as pd
import numpy as np
import pytest
from datetime import datetime, timezone, timedelta

from atr_adaptive_laguerre import (
    ATRAdaptiveLaguerreRSI,
    ATRAdaptiveLaguerreRSIConfig,
)


class TestAvailabilityColumn:
    """Test suite for availability_column parameter."""

    def test_availability_column_prevents_leakage(self) -> None:
        """
        Test that availability_column prevents data leakage in multi-interval mode.

        Validates that features calculated with full dataset match features
        calculated with only past data at each validation point.
        """
        # Create test data
        start_time = datetime(2025, 1, 1, tzinfo=timezone.utc)
        timestamps = [start_time + timedelta(hours=2 * i) for i in range(400)]

        data = pd.DataFrame(
            {
                "date": timestamps,
                "actual_ready_time": timestamps,
                "open": [100 + 5 * np.sin(i / 10) for i in range(400)],
                "high": [105 + 5 * np.sin(i / 10) for i in range(400)],
                "low": [95 + 5 * np.sin(i / 10) for i in range(400)],
                "close": [100 + 5 * np.sin(i / 10) for i in range(400)],
                "volume": [1000000] * 400,
            }
        )

        # Configure with availability_column
        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=4,
            multiplier_2=12,
            filter_redundancy=False,
            availability_column="actual_ready_time",
        )
        indicator = ATRAdaptiveLaguerreRSI(config)

        # Full data features
        features_full = indicator.fit_transform_features(data)

        # Validation point
        validation_idx = 380

        # Prediction data (only past data)
        pred_data = data.iloc[: validation_idx + 1].copy()
        features_pred = indicator.fit_transform_features(pred_data)

        # Compare features
        full_row = features_full.iloc[validation_idx]
        pred_row = features_pred.iloc[-1]

        # Check critical features
        for feature in ["rsi_base", "rsi_mult1", "rsi_mult2"]:
            diff = abs(full_row[feature] - pred_row[feature])
            assert diff < 1e-5, (
                f"Data leakage detected in {feature}: "
                f"full={full_row[feature]:.6f}, pred={pred_row[feature]:.6f}, "
                f"diff={diff:.10f}"
            )

    def test_availability_column_with_delay(self) -> None:
        """
        Test availability_column with realistic data delay.

        Simulates a 2-hour delay between bar close and data availability.
        """
        start_time = datetime(2025, 1, 1, tzinfo=timezone.utc)
        timestamps = [start_time + timedelta(hours=2 * i) for i in range(400)]
        ready_times = [t + timedelta(hours=2) for t in timestamps]  # 2h delay

        data = pd.DataFrame(
            {
                "date": timestamps,
                "actual_ready_time": ready_times,
                "open": [100 + 5 * np.sin(i / 10) for i in range(400)],
                "high": [105 + 5 * np.sin(i / 10) for i in range(400)],
                "low": [95 + 5 * np.sin(i / 10) for i in range(400)],
                "close": [100 + 5 * np.sin(i / 10) for i in range(400)],
                "volume": [1000000] * 400,
            }
        )

        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=4,
            multiplier_2=12,
            filter_redundancy=False,
            availability_column="actual_ready_time",
        )
        indicator = ATRAdaptiveLaguerreRSI(config)

        # Full data
        features_full = indicator.fit_transform_features(data)

        # Prediction at validation time
        validation_idx = 380
        validation_ready_time = ready_times[validation_idx]
        pred_data = data[data["actual_ready_time"] <= validation_ready_time].copy()

        features_pred = indicator.fit_transform_features(pred_data)

        # Features should match at corresponding rows
        matching_idx = len(pred_data) - 1
        full_row = features_full.iloc[matching_idx]
        pred_row = features_pred.iloc[-1]

        for feature in ["rsi_base", "rsi_mult1", "rsi_mult2"]:
            diff = abs(full_row[feature] - pred_row[feature])
            assert diff < 1e-5, (
                f"Data leakage with delay in {feature}: diff={diff:.10f}"
            )

    def test_availability_column_missing_raises_error(self) -> None:
        """Test that missing availability_column raises clear error."""
        data = pd.DataFrame(
            {
                "date": pd.date_range("2025-01-01", periods=400, freq="1h"),
                "open": [100] * 400,
                "high": [105] * 400,
                "low": [95] * 400,
                "close": [100] * 400,
                "volume": [1000000] * 400,
            }
        )

        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=4,
            multiplier_2=12,
            availability_column="actual_ready_time",  # Column doesn't exist
        )
        indicator = ATRAdaptiveLaguerreRSI(config)

        with pytest.raises(ValueError, match="availability_column.*not found"):
            indicator.fit_transform_features(data)

    def test_availability_column_none_uses_standard_processing(self) -> None:
        """Test that availability_column=None uses standard processing."""
        data = pd.DataFrame(
            {
                "date": pd.date_range("2025-01-01", periods=400, freq="2h"),
                "open": [100] * 400,
                "high": [105] * 400,
                "low": [95] * 400,
                "close": [100] * 400,
                "volume": [1000000] * 400,
            }
        )

        # Without availability_column (standard processing)
        config_standard = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=4,
            multiplier_2=12,
            filter_redundancy=False,
            availability_column=None,
        )
        indicator_standard = ATRAdaptiveLaguerreRSI(config_standard)
        features_standard = indicator_standard.fit_transform_features(data)

        # Verify it runs without error
        assert len(features_standard) == len(data)
        assert "rsi_base" in features_standard.columns
        assert "rsi_mult1" in features_standard.columns
        assert "rsi_mult2" in features_standard.columns

    def test_availability_column_with_redundancy_filtering(self) -> None:
        """Test that availability_column works with redundancy filtering."""
        data = pd.DataFrame(
            {
                "date": pd.date_range("2025-01-01", periods=400, freq="2h"),
                "actual_ready_time": pd.date_range(
                    "2025-01-01", periods=400, freq="2h"
                ),
                "open": [100 + 5 * np.sin(i / 10) for i in range(400)],
                "high": [105 + 5 * np.sin(i / 10) for i in range(400)],
                "low": [95 + 5 * np.sin(i / 10) for i in range(400)],
                "close": [100 + 5 * np.sin(i / 10) for i in range(400)],
                "volume": [1000000] * 400,
            }
        )

        config = ATRAdaptiveLaguerreRSIConfig.multi_interval(
            multiplier_1=4,
            multiplier_2=12,
            filter_redundancy=True,  # Enable filtering
            availability_column="actual_ready_time",
        )
        indicator = ATRAdaptiveLaguerreRSI(config)

        # Should work and return 85 features
        features = indicator.fit_transform_features(data)
        assert features.shape[1] == 85

        # Check no leakage
        validation_idx = 380
        features_full = features
        pred_data = data.iloc[: validation_idx + 1].copy()
        features_pred = indicator.fit_transform_features(pred_data)

        # Compare a few key features
        full_row = features_full.iloc[validation_idx]
        pred_row = features_pred.iloc[-1]

        for feature in [c for c in features.columns if "regime" in c][:3]:
            diff = abs(full_row[feature] - pred_row[feature])
            assert diff < 1e-5
