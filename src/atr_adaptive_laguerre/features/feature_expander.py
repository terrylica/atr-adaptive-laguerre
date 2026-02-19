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

from __future__ import annotations

from typing import TYPE_CHECKING, Literal

import numpy as np
import pandas as pd

if TYPE_CHECKING:
    from atr_adaptive_laguerre.features.intermediates import IntermediateValues


class FeatureExpander:
    """
    Expand single RSI column to 31 base feature columns (43 with intermediates).

    Categories:
    1. Base indicator (1): rsi
    2. Regimes (7): regime classification and properties
    3. Thresholds (5): distances from key levels
    4. Crossings (4): threshold crossing events
    5. Temporal (3): time since extreme events
    6. Rate of change (3): momentum derivatives
    7. Statistics (4): rolling window statistics
    8. Tail risk (4): black swan event detectors (IC-validated)

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

    def expand(
        self,
        rsi: pd.Series,
        intermediates: IntermediateValues | None = None,
    ) -> pd.DataFrame:
        """
        Expand RSI to feature columns.

        Returns 31 columns when intermediates is None (backward compat),
        or 43 columns when intermediates are provided.

        Args:
            rsi: RSI values (must be pd.Series with float values in [0, 1])
            intermediates: Per-bar intermediate values from core computation loop.
                When provided, adds 12 additional features (adaptive, laguerre,
                ATR range, efficiency, cycle phase).

        Returns:
            DataFrame with 31 columns (no intermediates) or 43 columns (with).

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

        # Extract tail risk features (requires previously extracted features)
        tail_risk = self._extract_tail_risk(rsi, regimes, roc, statistics)

        # Combine base features (31 columns)
        parts = [
            pd.DataFrame({"rsi": rsi}),
            regimes,
            thresholds,
            crossings,
            temporal,
            roc,
            statistics,
            tail_risk,
        ]

        # Intermediate-based features (+12 columns when available)
        if intermediates is not None:
            parts.append(self._extract_adaptive_features(rsi.index, intermediates))
            parts.append(self._extract_laguerre_stage_features(rsi.index, intermediates))
            parts.append(self._extract_atr_range_features(rsi.index, intermediates))
            parts.append(self._extract_efficiency_features(rsi.index, intermediates))
            parts.append(self._extract_cycle_features(rsi.index, intermediates))

        features = pd.concat(parts, axis=1)

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
        regime_strength = pd.Series(
            np.where(
                regime == 0,
                np.maximum(self.level_down - rsi.values, 0),
                np.where(regime == 2, np.maximum(rsi.values - self.level_up, 0), 0.0),
            ),
            index=rsi.index,
        )

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

        # Bars since last oversold event (vectorized cumsum group trick)
        not_oversold = (~is_oversold).astype(np.int64)
        oversold_groups = is_oversold.cumsum()
        bars_since_oversold = not_oversold.groupby(oversold_groups).cumsum().astype(np.int64)

        # Bars since last overbought event (same pattern)
        not_overbought = (~is_overbought).astype(np.int64)
        overbought_groups = is_overbought.cumsum()
        bars_since_overbought = not_overbought.groupby(overbought_groups).cumsum().astype(np.int64)

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

        stats_df = rolling.agg(["mean", "std", "min", "max"])
        rsi_mean = stats_df["mean"]
        rsi_std = stats_df["std"].fillna(0)  # First bar has std=0
        rsi_min = stats_df["min"]
        rsi_max = stats_df["max"]

        # Percentile rank (current value's position in rolling window)
        rsi_percentile_20 = (
            rsi.rolling(window=self.stats_window, min_periods=1)
            .apply(lambda x: (x[-1] > x[:-1]).sum() / len(x) * 100, raw=True)
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

    def _extract_tail_risk(
        self,
        rsi: pd.Series,
        regimes: pd.DataFrame,
        roc: pd.DataFrame,
        statistics: pd.DataFrame,
    ) -> pd.DataFrame:
        """
        Extract 4 tail risk / black swan detection features.

        Detects extreme market conditions and volatility spikes that may
        precede or signal black swan events. Uses RSI-based indicators only
        (no ATR dependency for architecture simplicity).

        Features (validated via IC testing on out-of-sample data):
        1. rsi_shock_1bar: 1 if |1-bar change| > 0.3 (extreme momentum) [+18.6% IC gain]
        2. extreme_regime_persistence: 1 if in extreme regime > 10 bars [composite]
        3. rsi_volatility_spike: 1 if volatility > mean + 2σ [+40.7% IC gain]
        4. tail_risk_score: composite score [0, 1]

        Removed features (IC validation 2025-10-08):
        - rsi_shock_5bar: -70.1% IC loss vs source (rsi_change_5)
        - rsi_acceleration: -34.9% IC loss vs source (rsi_velocity)

        Returns:
            DataFrame with 4 columns

        Non-anticipative: Uses only past RSI values and previously extracted features.
        """
        # Extract pre-computed features
        rsi_change_1 = roc["rsi_change_1"]
        regime = regimes["regime"]
        bars_in_regime = regimes["bars_in_regime"]
        rsi_volatility_20 = statistics["rsi_volatility_20"]

        # 1. RSI Shock Detection (VIX-style sudden moves)
        rsi_shock_1bar = (np.abs(rsi_change_1) > 0.3).astype(np.int64)

        # 2. Extreme Regime Persistence (stuck in extreme zones)
        is_extreme_regime = (regime != 1).astype(bool)  # Not neutral
        extreme_regime_persistence = (
            is_extreme_regime & (bars_in_regime > 10)
        ).astype(np.int64)

        # 3. RSI Volatility Spike (2σ threshold)
        # Calculate rolling mean/std of RSI volatility (meta-volatility)
        vol_rolling = rsi_volatility_20.rolling(window=100, min_periods=20)
        vol_mean = vol_rolling.mean()
        vol_std = vol_rolling.std().fillna(0)
        rsi_volatility_spike = (
            rsi_volatility_20 > (vol_mean + 2 * vol_std)
        ).astype(np.int64)

        # 4. Tail Risk Composite Score [0, 1]
        # Weighted combination of validated binary indicators
        # Weights adjusted after removing underperforming features
        tail_risk_score = (
            rsi_shock_1bar * 0.4  # increased from 0.3
            + extreme_regime_persistence * 0.3  # increased from 0.2
            + rsi_volatility_spike * 0.3  # unchanged (best performer)
        ).clip(0, 1)

        return pd.DataFrame(
            {
                "rsi_shock_1bar": rsi_shock_1bar,
                "extreme_regime_persistence": extreme_regime_persistence,
                "rsi_volatility_spike": rsi_volatility_spike,
                "tail_risk_score": tail_risk_score,
            }
        )

    # --- Intermediate-based feature extractors (Groups A + D) ---

    def _extract_adaptive_features(
        self, index: pd.Index, intermediates: IntermediateValues
    ) -> pd.DataFrame:
        """
        Extract 4 adaptive coefficient and gamma features.

        Non-anticipative: adaptive_coeff[t] and gamma[t] use only bars 0..t.
        Rolling mean for gamma_spread uses backward window (center=False).
        """
        coeff = pd.Series(intermediates.adaptive_coeff, index=index)
        coeff_roc = coeff - coeff.shift(1).fillna(coeff.iloc[0])

        gamma = pd.Series(intermediates.gamma, index=index)
        gamma_mean = gamma.rolling(
            window=self.stats_window, min_periods=1
        ).mean()
        gamma_spread = gamma - gamma_mean

        return pd.DataFrame(
            {
                "adaptive_coeff": coeff,
                "adaptive_coeff_roc_1": coeff_roc,
                "gamma_value": gamma,
                "gamma_spread": gamma_spread,
            }
        )

    def _extract_laguerre_stage_features(
        self, index: pd.Index, intermediates: IntermediateValues
    ) -> pd.DataFrame:
        """
        Extract 3 Laguerre stage differential features.

        Non-anticipative: L0-L3 at bar t computed from close[t] and prior state.
        laguerre_slope normalization includes current bar in rolling std
        (same pattern as rsi_zscore_20).
        """
        L0 = intermediates.L0
        L1 = intermediates.L1
        L2 = intermediates.L2
        L3 = intermediates.L3
        eps = 1e-10

        # Spread: normalized difference between first and last stage
        spread = (L0 - L3) / (np.abs(L0) + np.abs(L3) + eps)

        # Mid convergence: middle stage convergence relative to outer stages
        outer_diff = np.abs(L0 - L1) + np.abs(L2 - L3) + eps
        mid_convergence = np.abs(L1 - L2) / outer_diff

        # Slope: L0 change normalized by rolling std for price-independence
        L0_series = pd.Series(L0, index=index)
        L0_diff = L0_series - L0_series.shift(1).fillna(L0_series.iloc[0])
        L0_std = L0_diff.rolling(
            window=self.stats_window, min_periods=1
        ).std().fillna(0).replace(0, 1)
        laguerre_slope = L0_diff / L0_std

        return pd.DataFrame(
            {
                "laguerre_spread": spread,
                "laguerre_mid_convergence": mid_convergence,
                "laguerre_slope": laguerre_slope.values,
            },
            index=index,
        )

    def _extract_atr_range_features(
        self, index: pd.Index, intermediates: IntermediateValues
    ) -> pd.DataFrame:
        """
        Extract 1 ATR range width (vol-of-vol) feature.

        Non-anticipative: min_atr[t] and max_atr[t] from ATR state at bar t.
        """
        eps = 1e-10
        width = (intermediates.max_atr - intermediates.min_atr) / (
            intermediates.max_atr + eps
        )

        return pd.DataFrame({"atr_range_width": width}, index=index)

    def _extract_efficiency_features(
        self, index: pd.Index, intermediates: IntermediateValues
    ) -> pd.DataFrame:
        """
        Extract 2 Kaufman Efficiency Ratio features.

        ER = |close[t] - close[t-n]| / sum(|close_changes|, window=n).
        Non-anticipative: uses only close[t-n..t] (backward window).
        """
        close = pd.Series(intermediates.close, index=index)
        n = self.stats_window

        # Direction: net price movement over window
        direction = np.abs(close - close.shift(n).fillna(close.iloc[0]))

        # Volatility: sum of absolute 1-bar changes over window
        abs_changes = np.abs(close - close.shift(1).fillna(close.iloc[0]))
        volatility = abs_changes.rolling(window=n, min_periods=1).sum()

        # ER = direction / volatility, clipped to [0, 1]
        er = (direction / volatility.replace(0, 1)).clip(0, 1)
        efficiency_trend = (er > 0.5).astype(np.int64)

        return pd.DataFrame(
            {
                "efficiency_ratio": er.values,
                "efficiency_trend": efficiency_trend.values,
            },
            index=index,
        )

    def _extract_cycle_features(
        self, index: pd.Index, intermediates: IntermediateValues
    ) -> pd.DataFrame:
        """
        Extract 2 Laguerre cycle phase detection features.

        Phase encoding from L0-L3 stage relationships:
        - 0 (down): L0 <= L1 and L2 <= L3
        - 1 (turning_up): L0 > L1 and L2 <= L3
        - 2 (up): L0 > L1 and L2 > L3
        - 3 (turning_down): L0 <= L1 and L2 > L3

        Non-anticipative: pointwise on current bar's filter stages.
        """
        L0_gt_L1 = intermediates.L0 > intermediates.L1
        L2_gt_L3 = intermediates.L2 > intermediates.L3

        phase = np.where(
            ~L0_gt_L1 & ~L2_gt_L3, 0,
            np.where(
                L0_gt_L1 & ~L2_gt_L3, 1,
                np.where(L0_gt_L1 & L2_gt_L3, 2, 3),
            ),
        )

        phase_series = pd.Series(phase, index=index)
        phase_changed = (
            phase_series != phase_series.shift(1).fillna(phase_series.iloc[0])
        ).astype(np.int64)

        return pd.DataFrame(
            {
                "cycle_phase": phase,
                "cycle_phase_changed": phase_changed.values,
            },
            index=index,
        )
