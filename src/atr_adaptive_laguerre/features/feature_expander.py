"""
Feature expander: Convert single RSI column → 27 feature columns.

SLOs:
- Availability: 99.9% (validates inputs, explicit errors)
- Correctness: 100% (all features non-anticipative, ranges validated)
- Observability: Full type hints, per-category extraction logging
- Maintainability: Single responsibility per method, ≤50 lines

Error Handling: raise_and_propagate
- ValueError on invalid inputs (type, range, length violations)
- Propagate all pandas/numpy errors
"""

from typing import Literal

import numpy as np
import pandas as pd


class FeatureExpander:
    """
    Expand single RSI column to 27 feature columns.

    Categories:
    1. Base indicator (1): rsi
    2. Regimes (7): regime classification and properties
    3. Thresholds (5): distances from key levels
    4. Crossings (4): threshold crossing events
    5. Temporal (3): time since extreme events
    6. Rate of change (3): momentum derivatives
    7. Statistics (4): rolling window statistics

    Non-anticipative guarantee: All features[t] use only rsi[0:t].
    """

    def __init__(
        self,
        level_up: float = 0.85,
        level_down: float = 0.15,
        stats_window: int = 20,
        velocity_span: int = 5,
    ):
        """
        Initialize feature expander.

        Args:
            level_up: Upper threshold for regime classification (default 0.85)
            level_down: Lower threshold for regime classification (default 0.15)
            stats_window: Window size for rolling statistics (default 20)
            velocity_span: Span for velocity EMA calculation (default 5)

        Raises:
            ValueError: If level_down >= level_up
            ValueError: If levels not in (0, 1)
            ValueError: If windows not positive integers
        """
        if not (0 < level_down < level_up < 1):
            raise ValueError(
                f"Invalid levels: must have 0 < level_down ({level_down}) < "
                f"level_up ({level_up}) < 1"
            )

        if stats_window < 1 or velocity_span < 1:
            raise ValueError(
                f"Windows must be positive: stats_window={stats_window}, "
                f"velocity_span={velocity_span}"
            )

        self.level_up = level_up
        self.level_down = level_down
        self.stats_window = stats_window
        self.velocity_span = velocity_span

    def expand(self, rsi: pd.Series) -> pd.DataFrame:
        """
        Expand RSI to 27 feature columns.

        Args:
            rsi: RSI values (must be pd.Series with float values in [0, 1])

        Returns:
            DataFrame with 27 columns:
            - rsi (base)
            - regime, regime_bearish, regime_neutral, regime_bullish,
              regime_changed, bars_in_regime, regime_strength (7)
            - dist_overbought, dist_oversold, dist_midline,
              abs_dist_overbought, abs_dist_oversold (5)
            - cross_above_oversold, cross_below_overbought,
              cross_above_midline, cross_below_midline (4)
            - bars_since_oversold, bars_since_overbought,
              bars_since_extreme (3)
            - rsi_change_1, rsi_change_5, rsi_velocity (3)
            - rsi_percentile_20, rsi_zscore_20, rsi_volatility_20,
              rsi_range_20 (4)

        Raises:
            ValueError: If rsi not pd.Series
            ValueError: If rsi contains values outside [0, 1]
            ValueError: If rsi length < stats_window
        """
        # Validate input
        if not isinstance(rsi, pd.Series):
            raise ValueError(f"rsi must be pd.Series, got {type(rsi)}")

        if rsi.min() < 0 or rsi.max() > 1:
            raise ValueError(
                f"rsi must be in [0, 1], got range [{rsi.min():.4f}, {rsi.max():.4f}]"
            )

        if len(rsi) < self.stats_window:
            raise ValueError(
                f"rsi length ({len(rsi)}) must be >= stats_window ({self.stats_window})"
            )

        # Extract feature categories
        regimes = self._extract_regimes(rsi)
        thresholds = self._extract_thresholds(rsi)
        crossings = self._extract_crossings(rsi)
        temporal = self._extract_temporal(rsi)
        roc = self._extract_roc(rsi)
        statistics = self._extract_statistics(rsi)

        # Combine all features
        features = pd.concat(
            [
                pd.DataFrame({"rsi": rsi}),
                regimes,
                thresholds,
                crossings,
                temporal,
                roc,
                statistics,
            ],
            axis=1,
        )

        return features

    def _extract_regimes(self, rsi: pd.Series) -> pd.DataFrame:
        """
        Extract 7 regime classification features.

        Regimes:
        - 0 (bearish): rsi < level_down
        - 1 (neutral): level_down <= rsi <= level_up
        - 2 (bullish): rsi > level_up

        Returns:
            DataFrame with columns:
            - regime: int {0,1,2}
            - regime_bearish, regime_neutral, regime_bullish: one-hot {0,1}
            - regime_changed: 1 if regime differs from previous bar
            - bars_in_regime: consecutive bars in current regime
            - regime_strength: distance into extreme zone [0, 1]

        Non-anticipative: Uses only rsi[t] and regime[t-1].
        """
        # Classify regime (vectorized)
        regime = pd.Series(1, index=rsi.index, dtype=np.int64)  # Default: neutral
        regime[rsi < self.level_down] = 0  # Bearish
        regime[rsi > self.level_up] = 2  # Bullish

        # One-hot encoding
        regime_bearish = (regime == 0).astype(np.int64)
        regime_neutral = (regime == 1).astype(np.int64)
        regime_bullish = (regime == 2).astype(np.int64)

        # Regime changes (non-anticipative: compares with previous)
        regime_changed = (regime != regime.shift(1).fillna(regime.iloc[0])).astype(
            np.int64
        )

        # Bars in current regime (cumulative count, resets on regime change)
        bars_in_regime = (
            regime_changed.groupby((regime_changed == 1).cumsum()).cumsum()
        )

        # Regime strength (how deep into extreme zone)
        regime_strength = pd.Series(0.0, index=rsi.index)
        regime_strength[regime == 0] = np.maximum(self.level_down - rsi[regime == 0], 0)
        regime_strength[regime == 2] = np.maximum(rsi[regime == 2] - self.level_up, 0)

        return pd.DataFrame(
            {
                "regime": regime,
                "regime_bearish": regime_bearish,
                "regime_neutral": regime_neutral,
                "regime_bullish": regime_bullish,
                "regime_changed": regime_changed,
                "bars_in_regime": bars_in_regime,
                "regime_strength": regime_strength,
            }
        )

    def _extract_thresholds(self, rsi: pd.Series) -> pd.DataFrame:
        """
        Extract 5 threshold distance features.

        Returns:
            DataFrame with columns:
            - dist_overbought: rsi - level_up (negative if below)
            - dist_oversold: rsi - level_down
            - dist_midline: rsi - 0.5
            - abs_dist_overbought: |rsi - level_up|
            - abs_dist_oversold: |rsi - level_down|

        Non-anticipative: Uses only rsi[t].
        """
        return pd.DataFrame(
            {
                "dist_overbought": rsi - self.level_up,
                "dist_oversold": rsi - self.level_down,
                "dist_midline": rsi - 0.5,
                "abs_dist_overbought": np.abs(rsi - self.level_up),
                "abs_dist_oversold": np.abs(rsi - self.level_down),
            }
        )

    def _extract_crossings(self, rsi: pd.Series) -> pd.DataFrame:
        """
        Extract 4 threshold crossing features.

        Returns:
            DataFrame with columns:
            - cross_above_oversold: 1 if crossed above level_down
            - cross_below_overbought: 1 if crossed below level_up
            - cross_above_midline: 1 if crossed above 0.5
            - cross_below_midline: 1 if crossed below 0.5

        Non-anticipative: Compares rsi[t] with rsi[t-1].
        """
        rsi_prev = rsi.shift(1).fillna(rsi.iloc[0])

        cross_above_oversold = (
            (rsi_prev <= self.level_down) & (rsi > self.level_down)
        ).astype(np.int64)

        cross_below_overbought = (
            (rsi_prev >= self.level_up) & (rsi < self.level_up)
        ).astype(np.int64)

        cross_above_midline = ((rsi_prev <= 0.5) & (rsi > 0.5)).astype(np.int64)
        cross_below_midline = ((rsi_prev >= 0.5) & (rsi < 0.5)).astype(np.int64)

        return pd.DataFrame(
            {
                "cross_above_oversold": cross_above_oversold,
                "cross_below_overbought": cross_below_overbought,
                "cross_above_midline": cross_above_midline,
                "cross_below_midline": cross_below_midline,
            }
        )

    def _extract_temporal(self, rsi: pd.Series) -> pd.DataFrame:
        """
        Extract 3 temporal persistence features.

        Returns:
            DataFrame with columns:
            - bars_since_oversold: bars since rsi < level_down
            - bars_since_overbought: bars since rsi > level_up
            - bars_since_extreme: min of above two

        Non-anticipative: Cumulative count from past events.
        """
        is_oversold = rsi < self.level_down
        is_overbought = rsi > self.level_up

        # Bars since last oversold event
        bars_since_oversold = pd.Series(0, index=rsi.index, dtype=np.int64)
        counter = 0
        for i in range(len(rsi)):
            if is_oversold.iloc[i]:
                counter = 0
            else:
                counter += 1
            bars_since_oversold.iloc[i] = counter

        # Bars since last overbought event
        bars_since_overbought = pd.Series(0, index=rsi.index, dtype=np.int64)
        counter = 0
        for i in range(len(rsi)):
            if is_overbought.iloc[i]:
                counter = 0
            else:
                counter += 1
            bars_since_overbought.iloc[i] = counter

        # Min of both
        bars_since_extreme = np.minimum(bars_since_oversold, bars_since_overbought)

        return pd.DataFrame(
            {
                "bars_since_oversold": bars_since_oversold,
                "bars_since_overbought": bars_since_overbought,
                "bars_since_extreme": bars_since_extreme,
            }
        )

    def _extract_roc(self, rsi: pd.Series) -> pd.DataFrame:
        """
        Extract 3 rate of change features.

        Returns:
            DataFrame with columns:
            - rsi_change_1: rsi[t] - rsi[t-1]
            - rsi_change_5: rsi[t] - rsi[t-5]
            - rsi_velocity: EMA of rsi_change_1 (span=velocity_span)

        Non-anticipative: Uses only past RSI values.
        """
        rsi_change_1 = rsi - rsi.shift(1).fillna(rsi.iloc[0])
        rsi_change_5 = rsi - rsi.shift(5).fillna(rsi.iloc[0])

        # Velocity: EMA of 1-bar changes
        rsi_velocity = rsi_change_1.ewm(span=self.velocity_span, adjust=False).mean()

        return pd.DataFrame(
            {
                "rsi_change_1": rsi_change_1,
                "rsi_change_5": rsi_change_5,
                "rsi_velocity": rsi_velocity,
            }
        )

    def _extract_statistics(self, rsi: pd.Series) -> pd.DataFrame:
        """
        Extract 4 rolling window statistical features.

        Returns:
            DataFrame with columns:
            - rsi_percentile_20: percentile rank over rolling window
            - rsi_zscore_20: z-score over rolling window
            - rsi_volatility_20: standard deviation over rolling window
            - rsi_range_20: max - min over rolling window

        Non-anticipative: Rolling window uses only past values.
        """
        # Rolling statistics
        rolling = rsi.rolling(window=self.stats_window, min_periods=1)

        rsi_mean = rolling.mean()
        rsi_std = rolling.std().fillna(0)  # First bar has std=0
        rsi_min = rolling.min()
        rsi_max = rolling.max()

        # Percentile rank (current value's position in rolling window)
        rsi_percentile_20 = (
            rsi.rolling(window=self.stats_window, min_periods=1)
            .apply(lambda x: (x.iloc[-1] > x.iloc[:-1]).sum() / len(x) * 100, raw=False)
            .fillna(50.0)  # First bar: median rank
        )

        # Z-score (avoid division by zero)
        rsi_zscore_20 = (rsi - rsi_mean) / rsi_std.replace(0, 1)

        # Volatility
        rsi_volatility_20 = rsi_std

        # Range
        rsi_range_20 = rsi_max - rsi_min

        return pd.DataFrame(
            {
                "rsi_percentile_20": rsi_percentile_20,
                "rsi_zscore_20": rsi_zscore_20,
                "rsi_volatility_20": rsi_volatility_20,
                "rsi_range_20": rsi_range_20,
            }
        )
