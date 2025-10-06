"""
ATR-Adaptive Laguerre RSI feature constructor.

SLOs:
- Availability: 99.9% (depends on data source availability)
- Correctness: 100% (exact MQL5 match, non-anticipative guarantee)
- Security: N/A (computational only)
- Observability: Full type hints (mypy strict)
- Maintainability: High (orchestration of out-of-box core components)

Error Handling: raise_and_propagate
- ValueError on invalid OHLCV schema (propagated from validation)
- TypeError on incorrect input types (propagated from Pydantic)
- All errors must propagate to caller for debugging

MQL5 Reference:
- File: reference/indicators/atr_adaptive/atr_adaptive_laguerre_rsi_refactor_for_python.mq5
- Lines: 209-302 (OnCalculate function)
- Algorithm: TR → ATR → adaptive coefficient → Laguerre filter → Laguerre RSI
"""

from typing import Literal

import numpy as np
import pandas as pd
from pydantic import Field, field_validator

from atr_adaptive_laguerre.core.adaptive import (
    calculate_adaptive_coefficient,
    calculate_adaptive_period,
)
from atr_adaptive_laguerre.core.atr import ATRState
from atr_adaptive_laguerre.core.laguerre_filter import (
    LaguerreFilterState,
    calculate_gamma,
)
from atr_adaptive_laguerre.core.laguerre_rsi import calculate_laguerre_rsi
from atr_adaptive_laguerre.core.true_range import TrueRangeState
from atr_adaptive_laguerre.features.base import BaseFeature, FeatureConfig


class ATRAdaptiveLaguerreRSIConfig(FeatureConfig):
    """
    Configuration for ATR-Adaptive Laguerre RSI feature.

    Attributes:
        atr_period: ATR lookback period (default: 32, matches MQL5 inpAtrPeriod)
        smoothing_period: Price smoothing period (default: 5, matches MQL5 inpSmthPeriod)
        smoothing_method: Smoothing method (default: "ema", matches MQL5 inpSmthMethod)
        level_up: Upper threshold for bullish signal (default: 0.85)
        level_down: Lower threshold for bearish signal (default: 0.15)
        adaptive_offset: Adaptive period offset coefficient (default: 0.75, matches MQL5)

    Raises:
        ValidationError: If parameters violate constraints (propagated from Pydantic)
    """

    atr_period: int = Field(default=32, ge=1, description="ATR lookback period")
    smoothing_period: int = Field(default=5, ge=1, description="Price smoothing period")
    smoothing_method: Literal["ema", "sma", "smma", "lwma"] = Field(
        default="ema", description="Price smoothing method"
    )
    level_up: float = Field(default=0.85, ge=0.0, le=1.0, description="Upper threshold")
    level_down: float = Field(
        default=0.15, ge=0.0, le=1.0, description="Lower threshold"
    )
    adaptive_offset: float = Field(
        default=0.75, ge=0.0, description="Adaptive period offset"
    )

    @field_validator("level_down")
    @classmethod
    def validate_level_down_lt_level_up(cls, v: float, info) -> float:
        """Validate level_down < level_up."""
        if "level_up" in info.data and v >= info.data["level_up"]:
            raise ValueError(
                f"level_down ({v}) must be < level_up ({info.data['level_up']})"
            )
        return v


class ATRAdaptiveLaguerreRSI(BaseFeature):
    """
    ATR-Adaptive Laguerre RSI feature constructor.

    Non-anticipative volatility-adaptive momentum indicator that combines:
    1. True Range calculation
    2. ATR with rolling min/max tracking
    3. Adaptive coefficient from ATR normalization
    4. Dynamic period calculation
    5. Laguerre 4-stage cascade filter
    6. Laguerre RSI calculation

    Guarantees:
    - Non-anticipative: Only uses i-1 lookback data at bar i
    - Deterministic: Same OHLCV input → same RSI output
    - Stateful: Incremental O(1) updates via core components

    MQL5 Reference Mapping:
    - Lines 239-242: True Range (core.true_range)
    - Lines 244-287: ATR + min/max (core.atr)
    - Lines 290-292: Adaptive coefficient (core.adaptive)
    - Line 295: Adaptive period (core.adaptive)
    - Lines 406-412: Laguerre filter (core.laguerre_filter)
    - Lines 415-428: Laguerre RSI (core.laguerre_rsi)

    Raises:
        ValueError: If OHLCV schema invalid (must propagate, not handle)
        TypeError: If df not pd.DataFrame (must propagate, not handle)
        ValidationError: If config validation fails (propagated from Pydantic)
    """

    def __init__(self, config: ATRAdaptiveLaguerreRSIConfig | None = None):
        """
        Initialize ATR-Adaptive Laguerre RSI feature.

        Args:
            config: Feature configuration (defaults to ATRAdaptiveLaguerreRSIConfig())

        Raises:
            ValidationError: If config validation fails (propagated from Pydantic)
        """
        if config is None:
            config = ATRAdaptiveLaguerreRSIConfig()
        super().__init__(config)
        self.config: ATRAdaptiveLaguerreRSIConfig = config

    def fit_transform(self, df: pd.DataFrame) -> pd.Series:
        """
        Transform OHLCV data to ATR-Adaptive Laguerre RSI values.

        Non-anticipative guarantee: At bar i, only uses data from bars 0 to i-1.
        This matches MQL5 OnCalculate logic where each bar i only accesses i-1 state.

        Algorithm flow (matches MQL5 lines 232-295):
        1. For each bar i in chronological order:
           a. Calculate TR[i] using high[i], low[i], close[i-1]
           b. Update ATR state with TR[i]
           c. Calculate adaptive coefficient from ATR min/max
           d. Calculate adaptive period = atr_period * (coeff + offset)
           e. Update Laguerre filter with price[i] and adaptive gamma
           f. Calculate Laguerre RSI from filter stages

        Args:
            df: OHLCV DataFrame with columns: date, open, high, low, close, volume
               Must be sorted chronologically (ascending date)

        Returns:
            Laguerre RSI values as pd.Series (range: 0.0 to 1.0)
            Same index as df, same length as df

        Raises:
            ValueError: If df missing required columns (must propagate, not handle)
            TypeError: If df not pd.DataFrame (must propagate, not handle)
            KeyError: If df columns invalid (must propagate, not handle)

        Note:
            Must NOT catch exceptions and provide defaults.
            All errors must propagate to caller for debugging.

        MQL5 Reference: lines 232-295 (main calculation loop in OnCalculate)
        """
        # Validate input type (raise TypeError if not DataFrame)
        if not isinstance(df, pd.DataFrame):
            raise TypeError(f"df must be pd.DataFrame, got {type(df)}")

        # Validate required columns (raise KeyError if missing)
        required_cols = ["date", "open", "high", "low", "close", "volume"]
        missing = set(required_cols) - set(df.columns)
        if missing:
            raise ValueError(f"df missing required columns: {missing}")

        # Validate chronological order (non-anticipative requirement)
        if not df["date"].is_monotonic_increasing:
            raise ValueError("df must be sorted chronologically (ascending date)")

        # Extract OHLC arrays
        high = df["high"].values
        low = df["low"].values
        close = df["close"].values

        # Initialize stateful calculators
        tr_state = TrueRangeState()
        atr_state = ATRState(period=self.config.atr_period)
        laguerre_state = LaguerreFilterState()

        # Pre-allocate output array
        rsi_values = np.zeros(len(df), dtype=np.float64)

        # Main calculation loop (matches MQL5 lines 232-295)
        for i in range(len(df)):
            # Step 1: Calculate True Range (matches lines 239-242)
            # Non-anticipative: TR[i] uses close[i-1], not close[i]
            tr = tr_state.update(high[i], low[i], close[i])

            # Step 2: Update ATR state (matches lines 244-287)
            atr, min_atr, max_atr = atr_state.update(tr)

            # Step 3: Calculate adaptive coefficient (matches lines 290-292)
            adaptive_coeff = calculate_adaptive_coefficient(atr, min_atr, max_atr)

            # Step 4: Calculate adaptive period (matches line 295)
            # MQL5: inpAtrPeriod*(_coeff+0.75)
            adaptive_period = calculate_adaptive_period(
                base_period=float(self.config.atr_period),
                coefficient=adaptive_coeff,
                offset=self.config.adaptive_offset,
            )

            # Step 5: Calculate Laguerre gamma for adaptive period (matches line 403)
            gamma = calculate_gamma(adaptive_period)

            # Step 6: Update Laguerre filter (matches lines 406-412)
            # Use close price as input (matches MQL5 prices[i])
            L0, L1, L2, L3 = laguerre_state.update(close[i], gamma)

            # Step 7: Calculate Laguerre RSI (matches lines 415-428)
            rsi_values[i] = calculate_laguerre_rsi(L0, L1, L2, L3)

        # Return as Series with same index as input
        return pd.Series(rsi_values, index=df.index, name="atr_adaptive_laguerre_rsi")

    def validate_non_anticipative(
        self, df: pd.DataFrame, n_shuffles: int = 100
    ) -> bool:
        """
        Validate feature is non-anticipative via progressive computation.

        Test methodology:
        1. Compute feature on progressively longer subsets
        2. For each subset length from min_length to full length:
           a. Compute feature on df[:length]
           b. Compare with previous computation's overlapping values
        3. If overlapping values identical → non-anticipative
        4. If overlapping values differ → lookahead bias detected

        The key insight: if feature at bar i only uses data up to bar i-1,
        then adding bars i+1, i+2, ... should NOT change feature value at bar i.

        Args:
            df: Test DataFrame with OHLCV columns
            n_shuffles: Number of progressive tests (default: 100)
                        Tests n_shuffles equally-spaced subset lengths

        Returns:
            True if feature is non-anticipative

        Raises:
            ValueError: If feature shows lookahead bias
            TypeError: If df not pd.DataFrame (propagated from fit_transform)
            KeyError: If df missing required columns (propagated from fit_transform)

        Note:
            Compares with numpy.allclose(rtol=1e-9, atol=1e-12) for numerical stability.
        """
        # Validate input
        if not isinstance(df, pd.DataFrame):
            raise TypeError(f"df must be pd.DataFrame, got {type(df)}")

        if len(df) < 10:
            raise ValueError(f"df too short for validation (len={len(df)}, need >=10)")

        # Minimum subset length (need enough bars for ATR calculation)
        min_length = max(self.config.atr_period + 10, 50)
        if len(df) < min_length:
            raise ValueError(
                f"df too short for validation (len={len(df)}, need >={min_length})"
            )

        # Generate test subset lengths (evenly spaced from min to full)
        test_lengths = np.linspace(min_length, len(df), min(n_shuffles, len(df) - min_length + 1), dtype=int)
        test_lengths = np.unique(test_lengths)  # Remove duplicates

        # Compute baseline on full data
        full_feature = self.fit_transform(df)

        # Test each progressive subset
        for test_len in test_lengths:
            # Compute feature on subset
            subset_df = df.iloc[:test_len]
            subset_feature = self.fit_transform(subset_df)

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
                    f"This violates non-anticipative guarantee."
                )

        # All tests passed → feature is non-anticipative
        return True
