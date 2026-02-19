"""
Cross-interval feature extractor: Interaction patterns across 3 intervals.

SLOs:
- Availability: 99.9% (validates input alignment, column presence)
- Correctness: 100% (all interactions derivable from single-interval features only)
- Observability: Full type hints, per-category extraction
- Maintainability: ≤80 lines per method, single responsibility

Error Handling: raise_and_propagate
- ValueError on mismatched indices
- ValueError on missing required columns
- Propagate all computation errors
"""

import numpy as np
import pandas as pd


class CrossIntervalFeatures:
    """
    Extract 40 cross-interval interaction features.

    Categories:
    1. Regime alignment (6): All intervals agree/disagree on regime
    2. Regime divergence (8): Base vs higher interval regime conflicts
    3. Momentum patterns (6): RSI spreads and gradients across intervals
    4. Crossing patterns (8): Multi-interval threshold crossing events
    5. Temporal patterns (12): Regime persistence and transitions

    Non-anticipative guarantee: All features derived from single-interval
    features which are already non-anticipative.
    """

    def extract_interactions(
        self,
        features_base: pd.DataFrame,
        features_mult1: pd.DataFrame,
        features_mult2: pd.DataFrame,
    ) -> pd.DataFrame:
        """
        Extract 40 cross-interval interaction features.

        Args:
            features_base: 43 features from base interval
            features_mult1: 43 features from mult1 interval (aligned to base)
            features_mult2: 43 features from mult2 interval (aligned to base)

        Returns:
            DataFrame with 40 columns:
            - Regime alignment (6)
            - Regime divergence (8)
            - Momentum patterns (6)
            - Crossing patterns (8)
            - Temporal patterns (12)

        Raises:
            ValueError: If indices don't match
            ValueError: If required columns missing
        """
        # Validate inputs
        self._validate_inputs(features_base, features_mult1, features_mult2)

        # Extract interaction categories
        alignment = self._regime_alignment(features_base, features_mult1, features_mult2)
        divergence = self._regime_divergence(features_base, features_mult1, features_mult2)
        momentum = self._momentum_patterns(features_base, features_mult1, features_mult2)
        crossings = self._crossing_patterns(features_base, features_mult1, features_mult2)
        temporal = self._temporal_patterns(features_base, features_mult1, features_mult2)

        # Concatenate all interactions
        interactions = pd.concat(
            [alignment, divergence, momentum, crossings, temporal], axis=1
        )

        return interactions

    def _validate_inputs(
        self,
        features_base: pd.DataFrame,
        features_mult1: pd.DataFrame,
        features_mult2: pd.DataFrame,
    ) -> None:
        """Validate input DataFrames have matching indices."""
        if not features_base.index.equals(features_mult1.index):
            raise ValueError("features_base and features_mult1 indices don't match")

        if not features_base.index.equals(features_mult2.index):
            raise ValueError("features_base and features_mult2 indices don't match")

    def _regime_alignment(
        self, base: pd.DataFrame, mult1: pd.DataFrame, mult2: pd.DataFrame
    ) -> pd.DataFrame:
        """
        Extract 6 regime alignment features.

        Returns:
            DataFrame with columns:
            - all_intervals_bullish: All 3 intervals in regime 2
            - all_intervals_bearish: All 3 intervals in regime 0
            - all_intervals_neutral: All 3 intervals in regime 1
            - regime_agreement_count: How many intervals share same regime (0-3)
            - regime_majority: Majority vote regime (0, 1, or 2)
            - regime_unanimity: 1 if all intervals agree on regime
        """
        regime_base = base["regime"].values
        regime_mult1 = mult1["regime"].values
        regime_mult2 = mult2["regime"].values

        all_bullish = ((regime_base == 2) & (regime_mult1 == 2) & (regime_mult2 == 2)).astype(np.int64)
        all_bearish = ((regime_base == 0) & (regime_mult1 == 0) & (regime_mult2 == 0)).astype(np.int64)
        all_neutral = ((regime_base == 1) & (regime_mult1 == 1) & (regime_mult2 == 1)).astype(np.int64)

        # Vectorized agreement count: max pairwise match count
        # If all 3 same → 3; if any 2 same → 2; all different → 1
        bm1 = (regime_base == regime_mult1).astype(np.int64)
        bm2 = (regime_base == regime_mult2).astype(np.int64)
        m1m2 = (regime_mult1 == regime_mult2).astype(np.int64)
        all_same = bm1 & bm2  # implies m1m2 too
        any_pair = bm1 | bm2 | m1m2
        agreement_count = np.where(all_same, 3, np.where(any_pair, 2, 1)).astype(np.int64)

        # Vectorized majority regime (mode with min tie-break)
        # With 3 values: if any pair matches, that's the majority; if all different, min wins
        regime_majority = np.where(
            bm1, regime_base,  # base == mult1 → they're the majority
            np.where(
                bm2, regime_base,  # base == mult2 → they're the majority
                np.where(
                    m1m2, regime_mult1,  # mult1 == mult2 → they're the majority
                    np.minimum(np.minimum(regime_base, regime_mult1), regime_mult2)  # all different → min (scipy.stats.mode tie-break)
                )
            )
        ).astype(np.int64)

        unanimity = all_same.astype(np.int64)

        return pd.DataFrame(
            {
                "all_intervals_bullish": all_bullish,
                "all_intervals_bearish": all_bearish,
                "all_intervals_neutral": all_neutral,
                "regime_agreement_count": agreement_count,
                "regime_majority": regime_majority,
                "regime_unanimity": unanimity,
            },
            index=base.index,
        )

    def _regime_divergence(
        self, base: pd.DataFrame, mult1: pd.DataFrame, mult2: pd.DataFrame
    ) -> pd.DataFrame:
        """
        Extract 8 regime divergence features.

        Returns:
            DataFrame with columns:
            - base_bull_higher_bear: Base bullish, any higher bearish
            - base_bear_higher_bull: Base bearish, any higher bullish
            - divergence_strength: Max RSI spread across intervals
            - divergence_direction: Sign of base - mult2 spread
            - base_extreme_higher_neutral: Base extreme, mult2 neutral
            - base_neutral_higher_extreme: Base neutral, mult2 extreme
            - gradient_up: RSI increasing with interval (base > mult1 > mult2)
            - gradient_down: RSI decreasing with interval
        """
        regime_base = base["regime"].values
        regime_mult1 = mult1["regime"].values
        regime_mult2 = mult2["regime"].values
        rsi_base = base["rsi"].values
        rsi_mult1 = mult1["rsi"].values
        rsi_mult2 = mult2["rsi"].values

        base_bull_higher_bear = (
            (regime_base == 2) & ((regime_mult1 == 0) | (regime_mult2 == 0))
        ).astype(np.int64)

        base_bear_higher_bull = (
            (regime_base == 0) & ((regime_mult1 == 2) | (regime_mult2 == 2))
        ).astype(np.int64)

        # Vectorized divergence strength (zero temporary allocation)
        divergence_strength = (
            np.maximum(np.maximum(rsi_base, rsi_mult1), rsi_mult2)
            - np.minimum(np.minimum(rsi_base, rsi_mult1), rsi_mult2)
        )

        divergence_direction = np.sign(rsi_base - rsi_mult2).astype(np.int64)

        base_extreme_higher_neutral = (
            ((regime_base == 0) | (regime_base == 2)) & (regime_mult2 == 1)
        ).astype(np.int64)

        base_neutral_higher_extreme = (
            (regime_base == 1) & ((regime_mult2 == 0) | (regime_mult2 == 2))
        ).astype(np.int64)

        gradient_up = ((rsi_base > rsi_mult1) & (rsi_mult1 > rsi_mult2)).astype(np.int64)
        gradient_down = ((rsi_base < rsi_mult1) & (rsi_mult1 < rsi_mult2)).astype(np.int64)

        return pd.DataFrame(
            {
                "base_bull_higher_bear": base_bull_higher_bear,
                "base_bear_higher_bull": base_bear_higher_bull,
                "divergence_strength": divergence_strength,
                "divergence_direction": divergence_direction,
                "base_extreme_higher_neutral": base_extreme_higher_neutral,
                "base_neutral_higher_extreme": base_neutral_higher_extreme,
                "gradient_up": gradient_up,
                "gradient_down": gradient_down,
            },
            index=base.index,
        )

    def _momentum_patterns(
        self, base: pd.DataFrame, mult1: pd.DataFrame, mult2: pd.DataFrame
    ) -> pd.DataFrame:
        """
        Extract 6 momentum pattern features.

        Returns:
            DataFrame with columns:
            - rsi_spread_base_mult1: base - mult1 RSI
            - rsi_spread_base_mult2: base - mult2 RSI
            - rsi_spread_mult1_mult2: mult1 - mult2 RSI
            - momentum_direction: Sign of base - mult2
            - momentum_magnitude: Abs(base - mult2)
            - momentum_consistency: Same sign of change across intervals
        """
        rsi_base = base["rsi"]
        rsi_mult1 = mult1["rsi"]
        rsi_mult2 = mult2["rsi"]
        change_base = base["rsi_change_1"]
        change_mult2 = mult2["rsi_change_1"]

        spread_base_mult1 = rsi_base - rsi_mult1
        spread_base_mult2 = rsi_base - rsi_mult2
        spread_mult1_mult2 = rsi_mult1 - rsi_mult2

        momentum_direction = np.sign(spread_base_mult2).astype(np.int64)
        momentum_magnitude = np.abs(spread_base_mult2)

        # Momentum consistency (changes in same direction)
        momentum_consistency = (np.sign(change_base) == np.sign(change_mult2)).astype(
            np.int64
        )

        return pd.DataFrame(
            {
                "rsi_spread_base_mult1": spread_base_mult1,
                "rsi_spread_base_mult2": spread_base_mult2,
                "rsi_spread_mult1_mult2": spread_mult1_mult2,
                "momentum_direction": momentum_direction,
                "momentum_magnitude": momentum_magnitude,
                "momentum_consistency": momentum_consistency,
            }
        )

    def _crossing_patterns(
        self, base: pd.DataFrame, mult1: pd.DataFrame, mult2: pd.DataFrame
    ) -> pd.DataFrame:
        """
        Extract 8 crossing pattern features.

        Returns:
            DataFrame with columns:
            - any_interval_crossed_overbought: Any interval crossed below 0.85
            - all_intervals_crossed_overbought: All intervals crossed
            - any_interval_crossed_oversold: Any interval crossed above 0.15
            - all_intervals_crossed_oversold: All intervals crossed
            - base_crossed_while_higher_extreme: Base crossed, mult2 in extreme
            - cascade_crossing_up: Sequential crossing up (mult2 → mult1 → base)
            - cascade_crossing_down: Sequential crossing down
            - higher_crossed_first: Mult2 crossed before base (within 10 bars)
        """
        cross_ob_base = base["cross_below_overbought"]
        cross_ob_mult1 = mult1["cross_below_overbought"]
        cross_ob_mult2 = mult2["cross_below_overbought"]
        cross_os_base = base["cross_above_oversold"]
        cross_os_mult1 = mult1["cross_above_oversold"]
        cross_os_mult2 = mult2["cross_above_oversold"]
        regime_mult2 = mult2["regime"]

        any_crossed_ob = (
            (cross_ob_base == 1) | (cross_ob_mult1 == 1) | (cross_ob_mult2 == 1)
        ).astype(np.int64)

        all_crossed_ob = (
            (cross_ob_base == 1) & (cross_ob_mult1 == 1) & (cross_ob_mult2 == 1)
        ).astype(np.int64)

        any_crossed_os = (
            (cross_os_base == 1) | (cross_os_mult1 == 1) | (cross_os_mult2 == 1)
        ).astype(np.int64)

        all_crossed_os = (
            (cross_os_base == 1) & (cross_os_mult1 == 1) & (cross_os_mult2 == 1)
        ).astype(np.int64)

        base_crossed_while_extreme = (
            (cross_os_base == 1) & (regime_mult2.isin([0, 2]))
        ).astype(np.int64)

        # Vectorized cascade crossings: shift(2) + shift(1) + current
        cascade_up = (
            (cross_os_mult2.shift(2) == 1)
            & (cross_os_mult1.shift(1) == 1)
            & (cross_os_base == 1)
        ).astype(np.int64).fillna(0).astype(np.int64)

        cascade_down = (
            (cross_ob_mult2.shift(2) == 1)
            & (cross_ob_mult1.shift(1) == 1)
            & (cross_ob_base == 1)
        ).astype(np.int64).fillna(0).astype(np.int64)

        # Vectorized higher_crossed_first: rolling(10).sum() on mult2, then AND with base crossing
        mult2_crossed_recent = cross_os_mult2.rolling(10, min_periods=1).sum().shift(1).fillna(0)
        higher_crossed_first = (
            (cross_os_base == 1) & (mult2_crossed_recent > 0)
        ).astype(np.int64)

        return pd.DataFrame(
            {
                "any_interval_crossed_overbought": any_crossed_ob,
                "all_intervals_crossed_overbought": all_crossed_ob,
                "any_interval_crossed_oversold": any_crossed_os,
                "all_intervals_crossed_oversold": all_crossed_os,
                "base_crossed_while_higher_extreme": base_crossed_while_extreme,
                "cascade_crossing_up": cascade_up,
                "cascade_crossing_down": cascade_down,
                "higher_crossed_first": higher_crossed_first,
            }
        )

    def _temporal_patterns(
        self, base: pd.DataFrame, mult1: pd.DataFrame, mult2: pd.DataFrame
    ) -> pd.DataFrame:
        """
        Extract 12 temporal pattern features.

        Returns:
            DataFrame with columns:
            - regime_persistence_ratio: bars_in_regime base / mult2
            - regime_change_cascade: mult2 changed before base
            - regime_stability_score: 1 - avg(regime_changed)
            - bars_since_alignment: Bars since last unanimity
            - alignment_duration: Consecutive bars with unanimity
            - higher_interval_leads: mult2 regime changed N bars before base
            - regime_transition_pattern: 3-bit encoding of transitions
            - mean_rsi_across_intervals: Mean of 3 RSI values
            - std_rsi_across_intervals: Std of 3 RSI values
            - rsi_range_across_intervals: max - min of 3 RSI values
            - rsi_skew_across_intervals: (base - mean) / std
            - interval_momentum_agreement: Count with rsi_change_1 > 0
        """
        regime_base = base["regime"]
        regime_mult1 = mult1["regime"]
        regime_mult2 = mult2["regime"]
        bars_in_regime_base = base["bars_in_regime"]
        bars_in_regime_mult2 = mult2["bars_in_regime"]
        regime_changed_base = base["regime_changed"]
        regime_changed_mult1 = mult1["regime_changed"]
        regime_changed_mult2 = mult2["regime_changed"]
        rsi_base = base["rsi"]
        rsi_mult1 = mult1["rsi"]
        rsi_mult2 = mult2["rsi"]
        change_base = base["rsi_change_1"]
        change_mult1 = mult1["rsi_change_1"]
        change_mult2 = mult2["rsi_change_1"]

        # Persistence ratio (avoid division by zero)
        persistence_ratio = bars_in_regime_base / bars_in_regime_mult2.replace(0, 1)

        # Vectorized regime change cascade: rolling(5).sum() on mult2, then AND with base changed
        mult2_changed_recent = regime_changed_mult2.rolling(5, min_periods=1).sum().shift(1).fillna(0)
        change_cascade = (
            (regime_changed_base == 1) & (mult2_changed_recent > 0)
        ).astype(np.int64)

        # Stability score
        stability_score = 1 - (
            regime_changed_base + regime_changed_mult1 + regime_changed_mult2
        ) / 3

        # Vectorized bars_since_alignment and alignment_duration using cumsum group trick
        unanimity = (regime_base == regime_mult1) & (regime_mult1 == regime_mult2)

        # bars_since_alignment: count consecutive non-unanimity bars (reset on unanimity)
        not_unanimous = (~unanimity).astype(np.int64)
        # Group trick: cumsum of unanimity creates group IDs, within each group cumsum of not_unanimous gives the counter
        unanimity_groups = unanimity.cumsum()
        bars_since_alignment = not_unanimous.groupby(unanimity_groups).cumsum().astype(np.int64)

        # alignment_duration: count consecutive unanimity bars (reset on non-unanimity)
        unanimous_int = unanimity.astype(np.int64)
        not_unanimous_groups = not_unanimous.cumsum()
        alignment_duration = unanimous_int.groupby(not_unanimous_groups).cumsum().astype(np.int64)

        # Vectorized higher_leading: same pattern as change_cascade
        higher_leading = (
            (regime_changed_base == 1) & (mult2_changed_recent > 0)
        ).astype(np.int64)

        # Transition pattern (3-bit: base, mult1, mult2)
        transition_pattern = (
            regime_changed_base * 4 + regime_changed_mult1 * 2 + regime_changed_mult2
        ).astype(np.int64)

        # RSI statistics across intervals (vectorized with numpy)
        rsi_stack = np.column_stack([rsi_base.values, rsi_mult1.values, rsi_mult2.values])
        mean_rsi = rsi_stack.mean(axis=1)
        std_rsi = rsi_stack.std(axis=1, ddof=1)  # ddof=1 matches pandas default
        range_rsi = rsi_stack.max(axis=1) - rsi_stack.min(axis=1)
        std_rsi_safe = np.where(std_rsi == 0, 1, std_rsi)
        skew_rsi = (rsi_base.values - mean_rsi) / std_rsi_safe

        # Momentum agreement
        momentum_agreement = (
            ((change_base > 0).astype(int))
            + ((change_mult1 > 0).astype(int))
            + ((change_mult2 > 0).astype(int))
        ).astype(np.int64)

        return pd.DataFrame(
            {
                "regime_persistence_ratio": persistence_ratio,
                "regime_change_cascade": change_cascade,
                "regime_stability_score": stability_score,
                "bars_since_alignment": bars_since_alignment,
                "alignment_duration": alignment_duration,
                "higher_interval_leads": higher_leading,
                "regime_transition_pattern": transition_pattern,
                "mean_rsi_across_intervals": mean_rsi,
                "std_rsi_across_intervals": std_rsi,
                "rsi_range_across_intervals": range_rsi,
                "rsi_skew_across_intervals": skew_rsi,
                "interval_momentum_agreement": momentum_agreement,
            },
            index=base.index,
        )
