"""
Adversarial regression tests for temporal leakage prevention.

Converted from one-time audits (/tmp/adversarial_temporal_audit.py,
/tmp/extreme_adversarial_audit.py) to permanent CI/CD regression suite.

SLOs:
- Correctness: 100% - Catches v1.0.4 boundary bug regression
- Observability: 100% - Detailed failure diagnostics
- Maintainability: 90% - Standard pytest patterns

Error Handling: raise_and_propagate
- All test failures include full context (timestamp, feature, diff)
- No silent failures or fallbacks

References:
- v1.0.4 bug: searchsorted(..., side='right') boundary condition
- v1.0.5 fix: searchsorted(..., side='left') ensures strict inequality
- Original audits: 624 test cases (462 + 162)
"""

import pytest
import numpy as np

from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI


class TestExhaustiveValidation:
    """
    Exhaustive timestamp validation (128 tests from adversarial audit).

    Tests temporal non-leakage at evenly-spaced timestamps across dataset.
    Original audit tested every 5th position; we test every 10th for CI performance.
    """

    @pytest.mark.parametrize("stride", [10])
    def test_exhaustive_timestamps_no_leakage(
        self,
        synthetic_ohlcv_data,
        multi_interval_config,
        temporal_validator,
        stride,
    ):
        """
        Test: No temporal leakage at every Nth timestamp.

        Original audit: 128 tests at every 5th position (1000 bars)
        This test: ~64 tests at every 10th position (faster CI)

        Validates v1.0.5 fix prevents regression of v1.0.4 boundary bug.

        Raises:
            AssertionError: If temporal leakage detected at any position
        """
        # Generate test data
        data = synthetic_ohlcv_data(n_bars=1000, base_interval_hours=2)
        config = multi_interval_config(multiplier_1=4, multiplier_2=12)
        indicator = ATRAdaptiveLaguerreRSI(config)

        # Test at every stride-th position after min_lookback
        min_lookback = indicator.min_lookback
        test_indices = list(range(min_lookback, len(data), stride))

        failures = []
        for idx in test_indices:
            try:
                temporal_validator(
                    data=data,
                    indicator=indicator,
                    validation_idx=idx,
                    features_to_check=["rsi", "rsi_mult1", "rsi_mult2"],
                )
            except AssertionError as e:
                failures.append({"idx": idx, "error": str(e)})

        if failures:
            failure_msg = f"Temporal leakage detected at {len(failures)}/{len(test_indices)} positions:\n"
            for f in failures[:5]:  # Show first 5
                failure_msg += f"  idx={f['idx']}: {f['error']}\n"
            raise AssertionError(failure_msg)


class TestMult1BoundaryConditions:
    """
    Mult1 boundary alignment tests (160 tests from adversarial audit).

    Critical: v1.0.4 bug had 25% failure rate at mult1 boundaries.
    Tests every timestamp that aligns with mult1 resampled bar boundaries.
    """

    def test_all_mult1_boundaries_no_leakage(
        self,
        synthetic_ohlcv_data,
        multi_interval_config,
        temporal_validator,
        boundary_timestamps,
    ):
        """
        Test: No temporal leakage at all mult1 boundary timestamps.

        Original audit: 160 mult1 boundary tests
        This is the CRITICAL test that would have caught v1.0.4 bug.

        Validates:
        - searchsorted(..., side='left') ensures availability < base_time
        - Bars with availability == base_time are correctly excluded

        Raises:
            AssertionError: If temporal leakage at any mult1 boundary
        """
        # Generate test data
        data = synthetic_ohlcv_data(n_bars=1000, base_interval_hours=2)
        config = multi_interval_config(multiplier_1=4, multiplier_2=12)
        indicator = ATRAdaptiveLaguerreRSI(config)

        # Find all mult1 boundary timestamps
        mult1_boundaries = boundary_timestamps(
            data=data,
            multiplier_1=4,
            multiplier_2=12,
            base_interval_hours=2,
            boundary_type="mult1",
        )

        # Filter to testable indices (after min_lookback)
        min_lookback = indicator.min_lookback
        test_boundaries = [idx for idx in mult1_boundaries if idx >= min_lookback]

        failures = []
        for idx in test_boundaries:
            try:
                temporal_validator(
                    data=data,
                    indicator=indicator,
                    validation_idx=idx,
                    features_to_check=["rsi_mult1"],  # Focus on mult1 feature
                )
            except AssertionError as e:
                failures.append({"idx": idx, "time": data.iloc[idx]["date"], "error": str(e)})

        if failures:
            failure_msg = (
                f"CRITICAL: Mult1 boundary leakage detected at {len(failures)}/{len(test_boundaries)} boundaries:\n"
                f"This indicates v1.0.4 regression (searchsorted bug)\n"
            )
            for f in failures[:5]:
                failure_msg += f"  idx={f['idx']} time={f['time']}: {f['error']}\n"
            raise AssertionError(failure_msg)


class TestMult2BoundaryConditions:
    """
    Mult2 boundary alignment tests (54 tests from adversarial audit).

    Similar to mult1 but for mult2 (12x) interval boundaries.
    """

    def test_all_mult2_boundaries_no_leakage(
        self,
        synthetic_ohlcv_data,
        multi_interval_config,
        temporal_validator,
        boundary_timestamps,
    ):
        """
        Test: No temporal leakage at all mult2 boundary timestamps.

        Original audit: 54 mult2 boundary tests

        Raises:
            AssertionError: If temporal leakage at any mult2 boundary
        """
        data = synthetic_ohlcv_data(n_bars=1000, base_interval_hours=2)
        config = multi_interval_config(multiplier_1=4, multiplier_2=12)
        indicator = ATRAdaptiveLaguerreRSI(config)

        mult2_boundaries = boundary_timestamps(
            data=data,
            multiplier_1=4,
            multiplier_2=12,
            base_interval_hours=2,
            boundary_type="mult2",
        )

        min_lookback = indicator.min_lookback
        test_boundaries = [idx for idx in mult2_boundaries if idx >= min_lookback]

        failures = []
        for idx in test_boundaries:
            try:
                temporal_validator(
                    data=data,
                    indicator=indicator,
                    validation_idx=idx,
                    features_to_check=["rsi_mult2"],
                )
            except AssertionError as e:
                failures.append({"idx": idx, "error": str(e)})

        if failures:
            failure_msg = f"Mult2 boundary leakage at {len(failures)}/{len(test_boundaries)} boundaries:\n"
            for f in failures[:5]:
                failure_msg += f"  idx={f['idx']}: {f['error']}\n"
            raise AssertionError(failure_msg)


class TestSimultaneousBoundaries:
    """
    Simultaneous mult1/mult2 boundary tests (25 tests from extreme audit).

    Tests LCM(mult1, mult2) boundary alignments where both intervals align.
    For mult1=4, mult2=12, LCM=12, so every 12 bars both boundaries align.
    """

    def test_simultaneous_mult1_mult2_boundaries(
        self,
        synthetic_ohlcv_data,
        multi_interval_config,
        temporal_validator,
        boundary_timestamps,
    ):
        """
        Test: No leakage when mult1 and mult2 boundaries align simultaneously.

        Original audit: 25 simultaneous boundary tests

        Raises:
            AssertionError: If temporal leakage at simultaneous boundaries
        """
        data = synthetic_ohlcv_data(n_bars=600, base_interval_hours=2)
        config = multi_interval_config(multiplier_1=4, multiplier_2=12)
        indicator = ATRAdaptiveLaguerreRSI(config)

        both_boundaries = boundary_timestamps(
            data=data,
            multiplier_1=4,
            multiplier_2=12,
            base_interval_hours=2,
            boundary_type="both",
        )

        min_lookback = indicator.min_lookback
        test_boundaries = [idx for idx in both_boundaries if idx >= min_lookback]

        failures = []
        for idx in test_boundaries:
            try:
                temporal_validator(
                    data=data,
                    indicator=indicator,
                    validation_idx=idx,
                    features_to_check=["rsi_mult1", "rsi_mult2"],
                )
            except AssertionError as e:
                failures.append({"idx": idx, "error": str(e)})

        if failures:
            raise AssertionError(
                f"Simultaneous boundary leakage at {len(failures)}/{len(test_boundaries)} positions"
            )


class TestRandomValidationPoints:
    """
    Monte Carlo random validation (100 tests from adversarial audit).

    Tests temporal safety at randomly selected timestamps to catch
    unexpected leakage at non-boundary positions.
    """

    @pytest.mark.parametrize("seed", range(5))  # 5 different random seeds
    def test_random_validation_points_no_leakage(
        self,
        synthetic_ohlcv_data,
        multi_interval_config,
        temporal_validator,
        seed,
    ):
        """
        Test: No temporal leakage at random validation points.

        Original audit: 100 random tests
        This test: 5 seeds × 20 random points = 100 tests total

        Raises:
            AssertionError: If temporal leakage at any random point
        """
        data = synthetic_ohlcv_data(n_bars=1000, base_interval_hours=2, price_seed=seed)
        config = multi_interval_config(multiplier_1=4, multiplier_2=12)
        indicator = ATRAdaptiveLaguerreRSI(config)

        min_lookback = indicator.min_lookback

        # Generate 20 random indices
        np.random.seed(seed)
        random_indices = np.random.choice(
            range(min_lookback, len(data)),
            size=min(20, len(data) - min_lookback),
            replace=False,
        )

        failures = []
        for idx in random_indices:
            try:
                temporal_validator(
                    data=data,
                    indicator=indicator,
                    validation_idx=int(idx),
                    features_to_check=["rsi", "rsi_mult1", "rsi_mult2"],
                )
            except AssertionError as e:
                failures.append({"idx": int(idx), "error": str(e)})

        if failures:
            raise AssertionError(
                f"Random point leakage at {len(failures)}/20 positions (seed={seed})"
            )


class TestDatasetBoundaries:
    """
    Dataset edge case tests (20 tests from adversarial audit).

    Tests temporal safety at dataset start and end boundaries.
    """

    def test_dataset_start_boundaries(
        self,
        synthetic_ohlcv_data,
        multi_interval_config,
        temporal_validator,
    ):
        """
        Test: No temporal leakage near dataset start.

        Tests first 10 positions after min_lookback.

        Raises:
            AssertionError: If temporal leakage at dataset start
        """
        data = synthetic_ohlcv_data(n_bars=600, base_interval_hours=2)
        config = multi_interval_config(multiplier_1=4, multiplier_2=12)
        indicator = ATRAdaptiveLaguerreRSI(config)

        min_lookback = indicator.min_lookback
        test_indices = range(min_lookback, min(min_lookback + 10, len(data)))

        failures = []
        for idx in test_indices:
            try:
                temporal_validator(
                    data=data,
                    indicator=indicator,
                    validation_idx=idx,
                )
            except AssertionError as e:
                failures.append({"idx": idx, "error": str(e)})

        if failures:
            raise AssertionError(f"Dataset start leakage at {len(failures)}/10 positions")

    def test_dataset_end_boundaries(
        self,
        synthetic_ohlcv_data,
        multi_interval_config,
        temporal_validator,
    ):
        """
        Test: No temporal leakage near dataset end.

        Tests last 10 positions of dataset.

        Raises:
            AssertionError: If temporal leakage at dataset end
        """
        data = synthetic_ohlcv_data(n_bars=600, base_interval_hours=2)
        config = multi_interval_config(multiplier_1=4, multiplier_2=12)
        indicator = ATRAdaptiveLaguerreRSI(config)

        min_lookback = indicator.min_lookback
        test_indices = range(max(len(data) - 10, min_lookback), len(data))

        failures = []
        for idx in test_indices:
            try:
                temporal_validator(
                    data=data,
                    indicator=indicator,
                    validation_idx=idx,
                )
            except AssertionError as e:
                failures.append({"idx": idx, "error": str(e)})

        if failures:
            raise AssertionError(f"Dataset end leakage at {len(failures)}/10 positions")


class TestOffByOneExhaustive:
    """
    Off-by-one exhaustive test (500 tests from extreme audit).

    Tests EVERY position in dataset to catch subtle indexing errors.
    Reduced to every 5th position for CI performance (100 tests).
    """

    def test_every_position_no_leakage(
        self,
        synthetic_ohlcv_data,
        multi_interval_config,
        temporal_validator,
    ):
        """
        Test: No off-by-one errors at any position.

        Original audit: Tested every position in 500-bar dataset
        This test: Every 5th position in 500-bar dataset (100 tests)

        Catches subtle indexing bugs like v1.0.4 searchsorted issue.

        Raises:
            AssertionError: If temporal leakage at any position
        """
        data = synthetic_ohlcv_data(n_bars=500, base_interval_hours=2)
        config = multi_interval_config(multiplier_1=4, multiplier_2=12)
        indicator = ATRAdaptiveLaguerreRSI(config)

        min_lookback = indicator.min_lookback
        test_indices = range(min_lookback, len(data), 5)  # Every 5th position

        failures = []
        for idx in test_indices:
            try:
                temporal_validator(
                    data=data,
                    indicator=indicator,
                    validation_idx=idx,
                    features_to_check=["rsi", "rsi_mult1", "rsi_mult2"],
                )
            except AssertionError as e:
                failures.append({"idx": idx})

        if failures:
            raise AssertionError(
                f"Off-by-one errors detected at {len(failures)}/{len(test_indices)} positions"
            )
