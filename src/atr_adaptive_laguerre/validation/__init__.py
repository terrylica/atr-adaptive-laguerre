"""Validation framework for feature quality assessment."""

from atr_adaptive_laguerre.validation.information_coefficient import (
    calculate_information_coefficient,
    validate_information_coefficient,
)
from atr_adaptive_laguerre.validation.non_anticipative import validate_non_anticipative
from atr_adaptive_laguerre.validation.ood_robustness import (
    split_by_trend,
    split_by_volatility,
    validate_ood_robustness,
)

__all__ = [
    # Non-anticipative validation
    "validate_non_anticipative",
    # Information Coefficient (IC) validation
    "calculate_information_coefficient",
    "validate_information_coefficient",
    # OOD robustness validation
    "validate_ood_robustness",
    "split_by_volatility",
    "split_by_trend",
]
