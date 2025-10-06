"""
ATR-Adaptive Laguerre RSI Feature Engineering Library.

Non-anticipative volatility-adaptive momentum indicator for seq-2-seq forecasting.
"""

__version__ = "0.1.0"

# Core components
from atr_adaptive_laguerre.core import (  # noqa: F401
    ATRState,
    LaguerreFilterState,
    TrueRangeState,
    calculate_adaptive_coefficient,
    calculate_gamma,
)

# Data adapters
from atr_adaptive_laguerre.data import BinanceAdapter  # noqa: F401

# Feature constructors
from atr_adaptive_laguerre.features import (  # noqa: F401
    ATRAdaptiveLaguerreRSI,
    ATRAdaptiveLaguerreRSIConfig,
    BaseFeature,
    FeatureConfig,
)

__all__ = [
    # Core
    "ATRState",
    "LaguerreFilterState",
    "TrueRangeState",
    "calculate_adaptive_coefficient",
    "calculate_gamma",
    # Data
    "BinanceAdapter",
    # Features
    "ATRAdaptiveLaguerreRSI",
    "ATRAdaptiveLaguerreRSIConfig",
    "BaseFeature",
    "FeatureConfig",
]
