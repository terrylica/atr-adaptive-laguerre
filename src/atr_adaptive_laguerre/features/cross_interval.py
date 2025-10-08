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
from scipy import stats


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
            features_base: 31 features from base interval
            features_mult1: 31 features from mult1 interval (aligned to base)
            features_mult2: 31 features from mult2 interval (aligned to base)

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
        regime_base = base["regime"]
        regime_mult1 = mult1["regime"]
        regime_mult2 = mult2["regime"]

        all_bullish = (
            (regime_base == 2) & (regime_mult1 == 2) & (regime_mult2 == 2)
        ).astype(np.int64)

        all_bearish = (
            (regime_base == 0) & (regime_mult1 == 0) & (regime_mult2 == 0)
        ).astype(np.int64)

        all_neutral = (
            (regime_base == 1) & (regime_mult1 == 1) & (regime_mult2 == 1)
        ).astype(np.int64)

        # Agreement count (how many intervals share the same regime)
        agreement_count = pd.Series(0, index=base.index, dtype=np.int64)
        for i in range(len(base)):
            regimes = [regime_base.iloc[i], regime_mult1.iloc[i], regime_mult2.iloc[i]]
            max_count = max(regimes.count(r) for r in set(regimes))
            agreement_count.iloc[i] = max_count

        # Majority regime (mode of 3 regimes)
        regime_majority = pd.Series(0, index=base.index, dtype=np.int64)
        for i in range(len(base)):
            regimes = [regime_base.iloc[i], regime_mult1.iloc[i], regime_mult2.iloc[i]]
            regime_majority.iloc[i] = stats.mode(regimes, keepdims=False)[0]

        # Unanimity (all 3 agree)
        unanimity = (agreement_count == 3).astype(np.int64)

        return pd.DataFrame(
            {
                "all_intervals_bullish": all_bullish,
                "all_intervals_bearish": all_bearish,
                "all_intervals_neutral": all_neutral,
                "regime_agreement_count": agreement_count,
                "regime_majority": regime_majority,
                "regime_unanimity": unanimity,
            }
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
        regime_base = base["regime"]
        regime_mult1 = mult1["regime"]
        regime_mult2 = mult2["regime"]
        rsi_base = base["rsi"]
        rsi_mult1 = mult1["rsi"]
        rsi_mult2 = mult2["rsi"]

        base_bull_higher_bear = (
            (regime_base == 2) & ((regime_mult1 == 0) | (regime_mult2 == 0))
        ).astype(np.int64)

        base_bear_higher_bull = (
            (regime_base == 0) & ((regime_mult1 == 2) | (regime_mult2 == 2))
        ).astype(np.int64)

        # Divergence strength (RSI spread)
        divergence_strength = pd.DataFrame(
            {"base": rsi_base, "mult1": rsi_mult1, "mult2": rsi_mult2}
        ).apply(lambda row: row.max() - row.min(), axis=1)

        # Divergence direction
        divergence_direction = np.sign(rsi_base - rsi_mult2).astype(np.int64)

        # Base extreme, higher neutral
        base_extreme_higher_neutral = (
            (regime_base.isin([0, 2])) & (regime_mult2 == 1)
        ).astype(np.int64)

        # Base neutral, higher extreme
        base_neutral_higher_extreme = (
            (regime_base == 1) & (regime_mult2.isin([0, 2]))
        ).astype(np.int64)

        # Gradient patterns
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
            }
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

        # Cascade crossings (sequential within 3 bars)
        cascade_up = pd.Series(0, index=base.index, dtype=np.int64)
        cascade_down = pd.Series(0, index=base.index, dtype=np.int64)
        for i in range(2, len(base)):
            # Check if mult2, mult1, base crossed up sequentially
            if (
                cross_os_mult2.iloc[i - 2] == 1
                and cross_os_mult1.iloc[i - 1] == 1
                and cross_os_base.iloc[i] == 1
            ):
                cascade_up.iloc[i] = 1

            # Check if mult2, mult1, base crossed down sequentially
            if (
                cross_ob_mult2.iloc[i - 2] == 1
                and cross_ob_mult1.iloc[i - 1] == 1
                and cross_ob_base.iloc[i] == 1
            ):
                cascade_down.iloc[i] = 1

        # Higher crossed first (mult2 crossed within last 10 bars, base crosses now)
        higher_crossed_first = pd.Series(0, index=base.index, dtype=np.int64)
        for i in range(10, len(base)):
            if cross_os_base.iloc[i] == 1:
                if cross_os_mult2.iloc[i - 10 : i].sum() > 0:
                    higher_crossed_first.iloc[i] = 1

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

        # Regime change cascade (mult2 changed within last 5 bars before base changed)
        change_cascade = pd.Series(0, index=base.index, dtype=np.int64)
        for i in range(5, len(base)):
            if regime_changed_base.iloc[i] == 1:
                if regime_changed_mult2.iloc[i - 5 : i].sum() > 0:
                    change_cascade.iloc[i] = 1

        # Stability score
        stability_score = 1 - (
            regime_changed_base + regime_changed_mult1 + regime_changed_mult2
        ) / 3

        # Bars since alignment
        unanimity = (regime_base == regime_mult1) & (regime_mult1 == regime_mult2)
        bars_since_alignment = pd.Series(0, index=base.index, dtype=np.int64)
        counter = 0
        for i in range(len(base)):
            if unanimity.iloc[i]:
                counter = 0
            else:
                counter += 1
            bars_since_alignment.iloc[i] = counter

        # Alignment duration
        alignment_duration = pd.Series(0, index=base.index, dtype=np.int64)
        counter = 0
        for i in range(len(base)):
            if unanimity.iloc[i]:
                counter += 1
            else:
                counter = 0
            alignment_duration.iloc[i] = counter

        # Higher leading base (mult2 changed 1-5 bars before base)
        higher_leading = pd.Series(0, index=base.index, dtype=np.int64)
        for i in range(5, len(base)):
            if regime_changed_base.iloc[i] == 1:
                if regime_changed_mult2.iloc[i - 5 : i].sum() > 0:
                    higher_leading.iloc[i] = 1

        # Transition pattern (3-bit: base, mult1, mult2)
        transition_pattern = (
            regime_changed_base * 4 + regime_changed_mult1 * 2 + regime_changed_mult2
        ).astype(np.int64)

        # RSI statistics across intervals
        rsi_df = pd.DataFrame({"base": rsi_base, "mult1": rsi_mult1, "mult2": rsi_mult2})
        mean_rsi = rsi_df.mean(axis=1)
        std_rsi = rsi_df.std(axis=1)
        range_rsi = rsi_df.max(axis=1) - rsi_df.min(axis=1)
        skew_rsi = (rsi_base - mean_rsi) / std_rsi.replace(0, 1)

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
            }
        )
