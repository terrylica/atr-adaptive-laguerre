"""
ATR-Adaptive Laguerre RSI Feature Engineering Library.

Non-anticipative volatility-adaptive momentum indicator for seq-2-seq forecasting.
"""

__version__ = "0.1.0"

# Core components available immediately
from atr_adaptive_laguerre.core import (  # noqa: F401
    ATRState,
    LaguerreFilterState,
    TrueRangeState,
    calculate_adaptive_coefficient,
    calculate_gamma,
)

__all__ = [
    "ATRState",
    "LaguerreFilterState",
    "TrueRangeState",
    "calculate_adaptive_coefficient",
    "calculate_gamma",
]
