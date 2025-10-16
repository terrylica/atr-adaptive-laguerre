"""
Pydantic models for backtesting.py adapter configuration and results.

Single source of truth for data contracts, JSON Schema generation, and AI-discoverable
documentation following Pydantic API Documentation Standard.

Architecture:
- Layer 1: Literal types define valid parameter values
- Layer 2: Pydantic models define data contracts with Field descriptions
- Layer 3: Rich docstrings in adapter functions (backtesting_adapter.py)

SLO Guarantees:
- Availability: 100% (interface definition, no runtime dependencies)
- Correctness: 100% (Pydantic v2 validation)
- Observability: Full type hints, JSON Schema generation
- Maintainability: Single source of truth eliminates doc fragmentation

Error Handling: raise_and_propagate (Pydantic raises ValidationError on invalid data)

Version: 2.0.0
"""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

# Layer 1: Literal Types - Define all valid values
FeatureNameType = Literal[
    # Base
    "rsi",
    # Regimes
    "regime",
    "regime_bearish",
    "regime_neutral",
    "regime_bullish",
    "regime_changed",
    "bars_in_regime",
    "regime_strength",
    # Thresholds
    "dist_overbought",
    "dist_oversold",
    "dist_midline",
    "abs_dist_overbought",
    "abs_dist_oversold",
    # Crossings
    "cross_above_oversold",
    "cross_below_overbought",
    "cross_above_midline",
    "cross_below_midline",
    # Temporal
    "bars_since_oversold",
    "bars_since_overbought",
    "bars_since_extreme",
    # Rate of change
    "rsi_change_1",
    "rsi_change_5",
    "rsi_velocity",
    # Statistics
    "rsi_percentile_20",
    "rsi_zscore_20",
    "rsi_volatility_20",
    "rsi_range_20",
    # Tail risk
    "rsi_shock_1bar",
    "extreme_regime_persistence",
    "rsi_volatility_spike",
    "tail_risk_score",
]


# Layer 2: Pydantic Models - Data contracts with validation
class IndicatorConfig(BaseModel):
    """
    Configuration for ATR-Adaptive Laguerre RSI indicator.

    Validates parameter constraints and provides JSON Schema for AI agents.
    All fields include descriptions for machine-readable documentation.
    """

    atr_period: int = Field(
        default=14,
        ge=10,
        le=30,
        description="ATR lookback period for volatility adaptation. "
        "Controls sensitivity to price volatility changes. "
        "Lower values (10-14) more responsive, higher values (20-30) more stable.",
    )
    smoothing_period: int = Field(
        default=5,
        ge=3,
        le=10,
        description="Price smoothing period for Laguerre filter cascade. "
        "Controls lag vs noise tradeoff. "
        "Lower values (3-5) faster response, higher values (7-10) smoother output.",
    )
    adaptive_offset: float = Field(
        default=0.75,
        ge=0.0,
        le=1.0,
        description="Adaptive period offset coefficient for gamma calculation. "
        "Controls baseline adaptation strength. "
        "Lower values increase sensitivity to volatility changes.",
    )
    level_up: float = Field(
        default=0.85,
        ge=0.5,
        le=1.0,
        description="Upper threshold for overbought signals. "
        "Values above this indicate strong bullish momentum. "
        "Typical range: 0.80-0.90.",
    )
    level_down: float = Field(
        default=0.15,
        ge=0.0,
        le=0.5,
        description="Lower threshold for oversold signals. "
        "Values below this indicate strong bearish momentum. "
        "Typical range: 0.10-0.20.",
    )

    model_config = ConfigDict(
        frozen=True,  # Immutable after creation
        json_schema_extra={
            "examples": [
                {
                    "atr_period": 14,
                    "smoothing_period": 5,
                    "adaptive_offset": 0.75,
                    "level_up": 0.85,
                    "level_down": 0.15,
                },
                {
                    "atr_period": 20,
                    "smoothing_period": 7,
                    "adaptive_offset": 0.5,
                    "level_up": 0.9,
                    "level_down": 0.1,
                },
            ]
        },
    )


class FeatureConfig(BaseModel):
    """
    Configuration for extracting single feature from 31-feature expansion.

    Extends IndicatorConfig with feature selection for multi-feature strategies.
    """

    feature_name: FeatureNameType = Field(
        default="rsi",
        description="Feature to extract from 31-feature expansion. "
        "Options: rsi (base), regime_* (classification), dist_* (thresholds), "
        "cross_* (signals), bars_since_* (temporal), rsi_*_20 (statistics), "
        "*_risk (tail risk indicators).",
    )
    atr_period: int = Field(
        default=14,
        ge=10,
        le=30,
        description="ATR lookback period for volatility adaptation. "
        "Controls sensitivity to price volatility changes.",
    )
    smoothing_period: int = Field(
        default=5,
        ge=3,
        le=10,
        description="Price smoothing period for Laguerre filter cascade. "
        "Controls lag vs noise tradeoff.",
    )
    adaptive_offset: float = Field(
        default=0.75,
        ge=0.0,
        le=1.0,
        description="Adaptive period offset coefficient for gamma calculation.",
    )
    level_up: float = Field(
        default=0.85,
        ge=0.5,
        le=1.0,
        description="Upper threshold for overbought signals.",
    )
    level_down: float = Field(
        default=0.15,
        ge=0.0,
        le=0.5,
        description="Lower threshold for oversold signals.",
    )

    model_config = ConfigDict(
        frozen=True,
        json_schema_extra={
            "examples": [
                {"feature_name": "rsi", "atr_period": 14, "smoothing_period": 5},
                {"feature_name": "regime", "atr_period": 20, "smoothing_period": 7},
                {
                    "feature_name": "tail_risk_score",
                    "atr_period": 14,
                    "smoothing_period": 5,
                },
            ]
        },
    )

    @staticmethod
    def supported_features() -> list[str]:
        """
        Return list of all supported feature names.

        Returns:
            List of 31 valid feature names

        Example:
            >>> FeatureConfig.supported_features()
            ['rsi', 'regime', 'regime_bearish', ...]
        """
        # Extract from Literal type
        from typing import get_args

        return list(get_args(FeatureNameType))
