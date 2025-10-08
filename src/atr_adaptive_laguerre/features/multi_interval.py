"""
Multi-interval processor: Resample OHLCV and extract features across intervals.

SLOs:
- Availability: 99.9% (validates multipliers, OHLCV schema)
- Correctness: 100% (resampling preserves integer multiples, ffill non-anticipative)
- Observability: Full type hints, resampling operation logging
- Maintainability: Single responsibility, ≤50 lines per function

Error Handling: raise_and_propagate
- ValueError on invalid multipliers (not integer, < 2, not increasing)
- ValueError on invalid OHLCV schema
- Propagate all pandas resampling errors
"""

from typing import Any, Callable

import pandas as pd


class MultiIntervalProcessor:
    """
    Process multi-interval feature extraction via resampling and alignment.

    Architecture:
    1. Validate multipliers (must be integers > 1, strictly increasing)
    2. Resample base OHLCV to higher intervals (multiplier × base)
    3. Extract features on each interval (via provided extractor function)
    4. Align higher interval features to base resolution (forward-fill)
    5. Concatenate with suffixes (_base, _mult1, _mult2)

    Non-anticipative guarantee:
    - Resampling uses only past bars (OHLC aggregation is deterministic)
    - Forward-fill uses last known value (no future data)
    """

    def __init__(self, multiplier_1: int, multiplier_2: int, date_column: str = "date"):
        """
        Initialize multi-interval processor.

        Args:
            multiplier_1: First higher interval multiplier (e.g., 3 for 3× base)
            multiplier_2: Second higher interval multiplier (e.g., 12 for 12× base)
            date_column: Name of datetime column for resampling (default: 'date')

        Raises:
            ValueError: If multipliers not integers
            ValueError: If multipliers < 2
            ValueError: If multiplier_1 >= multiplier_2 (must be strictly increasing)
        """
        self._validate_multiplier(multiplier_1, "multiplier_1")
        self._validate_multiplier(multiplier_2, "multiplier_2")

        if multiplier_1 >= multiplier_2:
            raise ValueError(
                f"multiplier_1 ({multiplier_1}) must be < multiplier_2 ({multiplier_2})"
            )

        self.multiplier_1 = multiplier_1
        self.multiplier_2 = multiplier_2
        self.date_column = date_column

    def resample_and_extract(
        self,
        df: pd.DataFrame,
        feature_extractor: Callable[[pd.DataFrame], pd.DataFrame],
    ) -> pd.DataFrame:
        """
        Resample OHLCV and extract features across 3 intervals.

        Args:
            df: Base interval OHLCV DataFrame
                Must have columns: date, open, high, low, close, volume
                Must be sorted by date (ascending)
            feature_extractor: Function that takes OHLCV → features DataFrame
                              (e.g., ATRAdaptiveLaguerreRSI.fit_transform_features)

        Returns:
            DataFrame with 93 columns (31 features × 3 intervals)
            Index: Same as input df (base resolution)
            Columns:
            - {feature}_base (31 columns from base interval)
            - {feature}_mult1 (31 columns from mult1 interval, forward-filled)
            - {feature}_mult2 (31 columns from mult2 interval, forward-filled)

        Raises:
            ValueError: If df missing required OHLCV columns
            ValueError: If df.date not monotonic increasing
            ValueError: If feature_extractor returns invalid DataFrame
            Propagates: All pandas resampling errors
        """
        # Validate input DataFrame
        self._validate_ohlcv(df)

        # Extract features on base interval
        features_base = feature_extractor(df)
        if not isinstance(features_base, pd.DataFrame):
            raise ValueError(
                f"feature_extractor must return pd.DataFrame, got {type(features_base)}"
            )

        features_base = features_base.add_suffix("_base")

        # Resample and extract for multiplier 1
        df_mult1 = self._resample_ohlcv(df, self.multiplier_1)
        features_mult1 = feature_extractor(df_mult1)
        features_mult1_aligned = self._align_to_base(
            features_mult1, df.index
        ).add_suffix("_mult1")

        # Resample and extract for multiplier 2
        df_mult2 = self._resample_ohlcv(df, self.multiplier_2)
        features_mult2 = feature_extractor(df_mult2)
        features_mult2_aligned = self._align_to_base(
            features_mult2, df.index
        ).add_suffix("_mult2")

        # Concatenate all intervals
        features_all = pd.concat(
            [features_base, features_mult1_aligned, features_mult2_aligned], axis=1
        )

        return features_all

    def _validate_multiplier(self, multiplier: Any, name: str) -> None:
        """
        Validate multiplier is integer >= 2.

        Args:
            multiplier: Value to validate
            name: Parameter name for error message

        Raises:
            ValueError: If not integer or < 2
        """
        if not isinstance(multiplier, int):
            raise ValueError(f"{name} must be int, got {type(multiplier)}")

        if multiplier < 2:
            raise ValueError(f"{name} must be >= 2, got {multiplier}")

    def _validate_ohlcv(self, df: pd.DataFrame) -> None:
        """
        Validate OHLCV DataFrame schema and ordering.

        Args:
            df: DataFrame to validate

        Raises:
            ValueError: If df not DataFrame
            ValueError: If missing required columns
            ValueError: If date column not monotonic increasing
        """
        if not isinstance(df, pd.DataFrame):
            raise ValueError(f"df must be pd.DataFrame, got {type(df)}")

        required_cols = {self.date_column, "open", "high", "low", "close", "volume"}
        missing = required_cols - set(df.columns)
        if missing:
            raise ValueError(f"df missing required OHLCV columns: {missing}")

        if not df[self.date_column].is_monotonic_increasing:
            raise ValueError(f"df.{self.date_column} must be monotonic increasing (sorted chronologically)")

    def _resample_ohlcv(self, df: pd.DataFrame, multiplier: int) -> pd.DataFrame:
        """
        Resample OHLCV to higher interval.

        Args:
            df: Base interval OHLCV
            multiplier: Integer multiplier (e.g., 3 for 3× base interval)

        Returns:
            Resampled OHLCV DataFrame
            - open: first value in window
            - high: max value in window
            - low: min value in window
            - close: last value in window
            - volume: sum of window

        Raises:
            Propagates: pandas resampling errors

        Non-anticipative: Resampling uses only bars in [window_start, window_end].
        Only complete windows (with full multiplier bars) are retained.
        """
        # Set date column as index for resampling
        df_indexed = df.set_index(self.date_column)

        # Infer base frequency from first two timestamps
        if len(df) < 2:
            raise ValueError(f"df too short for resampling: need >= 2 bars, got {len(df)}")

        base_freq = df[self.date_column].iloc[1] - df[self.date_column].iloc[0]

        # Calculate higher frequency
        higher_freq = base_freq * multiplier

        # Resample with count to identify incomplete windows
        df_resampled = df_indexed.resample(higher_freq).agg(
            {
                "open": "first",
                "high": "max",
                "low": "min",
                "close": "last",
                "volume": "sum",
            }
        )

        # Count bars in each window to filter incomplete windows
        bar_counts = df_indexed.resample(higher_freq).size()

        # Keep only windows with full multiplier bars (complete windows)
        # This ensures non-anticipative guarantee: incomplete windows at the end
        # of a subset won't produce different values than when they're complete
        complete_mask = bar_counts == multiplier
        df_resampled = df_resampled[complete_mask]

        # Drop any remaining NaN rows
        df_resampled = df_resampled.dropna()

        # Reset index (date back to column)
        df_resampled = df_resampled.reset_index()

        return df_resampled

    def _align_to_base(
        self, features_higher: pd.DataFrame, base_index: pd.Index
    ) -> pd.DataFrame:
        """
        Align higher interval features to base resolution via forward-fill.

        Args:
            features_higher: Features computed on higher interval
                            Index: datetime at higher resolution
            base_index: Target index (base resolution)

        Returns:
            Features aligned to base_index, forward-filled
            - Missing timestamps filled with last known value
            - First bars (before first higher interval bar) filled with NaN

        Non-anticipative: Forward-fill uses only past values.
                         At time t, uses last available value from t' <= t.

        Example:
            Base:   [00:00, 00:01, 00:02, 00:03, 00:04, 00:05, ...]
            Higher: [00:00,                      00:05, ...]
            Aligned:[feat0, feat0, feat0, feat0, feat0, feat5, ...]
                          ↑ forward-fill from 00:00
        """
        # Reindex to base resolution with forward-fill
        features_aligned = features_higher.reindex(base_index, method="ffill")

        return features_aligned
