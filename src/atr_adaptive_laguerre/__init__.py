"""
ATR-Adaptive Laguerre RSI Feature Engineering Library.

Non-anticipative volatility-adaptive momentum indicator for seq-2-seq forecasting.
"""

__version__ = "2.0.0"

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
    CrossIntervalFeatures,
    FeatureConfig,
    FeatureExpander,
    MultiIntervalProcessor,
)

# Validation framework
from atr_adaptive_laguerre.validation import (  # noqa: F401
    calculate_information_coefficient,
    validate_information_coefficient,
    validate_non_anticipative,
    validate_ood_robustness,
)

# backtesting.py adapter (v2.0.0 Pydantic API)
from atr_adaptive_laguerre.backtesting_adapter import (  # noqa: F401
    compute_feature,
    compute_indicator,
    make_indicator,
)
from atr_adaptive_laguerre.backtesting_models import (  # noqa: F401
    IndicatorConfig,
)
# Note: backtesting_models.FeatureConfig not exported at top level to avoid
# collision with features.FeatureConfig. Import explicitly if needed:
# from atr_adaptive_laguerre.backtesting_models import FeatureConfig

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
    "FeatureExpander",
    "MultiIntervalProcessor",
    "CrossIntervalFeatures",
    # Validation
    "validate_non_anticipative",
    "calculate_information_coefficient",
    "validate_information_coefficient",
    "validate_ood_robustness",
    # backtesting.py adapter (v2.0.0 Pydantic API)
    "IndicatorConfig",
    "compute_indicator",
    "compute_feature",
    "make_indicator",
]
