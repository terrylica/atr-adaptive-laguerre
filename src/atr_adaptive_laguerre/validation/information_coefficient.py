"""
Information Coefficient (IC) validation for predictive features.

SLOs:
- Availability: 100% (depends on scipy, out-of-box library)
- Correctness: 100% (Spearman rank correlation from scipy.stats)
- Security: N/A (validation only)
- Observability: Full type hints (mypy strict)
- Maintainability: High (out-of-box scipy implementation)

Error Handling: raise_and_propagate
- ValueError on insufficient data or invalid parameters
- TypeError on incorrect input types
- All scipy errors propagated (no handling)

Reference:
- IC Definition: Spearman rank correlation between feature[t] and forward_return[t+k]
- Success Criterion: IC > 0.03 (SOTA threshold for predictive features)
- Higher IC → stronger predictive power
"""

from typing import Literal

import numpy as np
import pandas as pd
from scipy import stats


def calculate_information_coefficient(
    feature: pd.Series,
    prices: pd.Series,
    forward_periods: int = 1,
    return_type: Literal["simple", "log"] = "log",
) -> float:
    """
    Calculate Information Coefficient (IC) via Spearman rank correlation.

    IC measures predictive power: correlation between feature[t] and return[t+k].

    Algorithm:
    1. Compute forward returns: return[t] = (price[t+k] - price[t]) / price[t]
    2. Align feature[t] with forward_return[t]
    3. Calculate Spearman rank correlation
    4. Return correlation coefficient

    Args:
        feature: Feature values at time t (e.g., ATR-Adaptive Laguerre RSI)
        prices: Price series (e.g., close prices)
        forward_periods: Look-ahead periods for return calculation (k in return[t+k])
                        Default: 1 (next-bar return)
        return_type: "simple" for (p[t+k] - p[t]) / p[t]
                     "log" for log(p[t+k] / p[t]) (default)

    Returns:
        Spearman rank correlation coefficient (range: -1.0 to 1.0)
        - IC > 0.03: Predictive feature (meets SOTA threshold)
        - IC > 0.05: Strong predictive feature
        - IC < 0.03: Weak/no predictive power
        - IC < 0: Inverse predictive power (feature negatively correlated)

    Raises:
        ValueError: If insufficient data, mismatched lengths, or invalid parameters
        TypeError: If inputs have incorrect types
        RuntimeError: If scipy.stats.spearmanr fails (propagated)

    Note:
        - Requires at least 30 overlapping data points for statistical significance
        - NaN values in feature or returns are dropped (pairwise)
        - Uses scipy.stats.spearmanr with nan_policy='omit'

    Example:
        >>> from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI
        >>> feature = ATRAdaptiveLaguerreRSI()
        >>> df = load_ohlcv_data()
        >>> feature_values = feature.fit_transform(df)
        >>> ic = calculate_information_coefficient(feature_values, df['close'], forward_periods=1)
        >>> assert ic > 0.03  # Feature has predictive power
    """
    # Validate input types
    if not isinstance(feature, pd.Series):
        raise TypeError(f"feature must be pd.Series, got {type(feature)}")

    if not isinstance(prices, pd.Series):
        raise TypeError(f"prices must be pd.Series, got {type(prices)}")

    if not isinstance(forward_periods, int) or forward_periods <= 0:
        raise TypeError(f"forward_periods must be positive int, got {forward_periods}")

    if return_type not in ("simple", "log"):
        raise ValueError(f"return_type must be 'simple' or 'log', got {return_type}")

    # Validate lengths
    if len(feature) != len(prices):
        raise ValueError(
            f"feature length ({len(feature)}) must match prices length ({len(prices)})"
        )

    # Validate sufficient data
    if len(feature) < forward_periods + 30:
        raise ValueError(
            f"Insufficient data: need at least {forward_periods + 30} bars, "
            f"got {len(feature)}"
        )

    # Calculate forward returns
    if return_type == "simple":
        # Simple return: (p[t+k] - p[t]) / p[t]
        # Use shift(-k) to get future prices: prices[t+k] / prices[t] - 1
        forward_returns = prices.shift(-forward_periods) / prices - 1
    else:
        # Log return: log(p[t+k] / p[t])
        # Use shift(-k) to get future prices: log(prices[t+k] / prices[t])
        forward_returns = np.log(prices.shift(-forward_periods) / prices)

    # Align feature[t] with forward_return[t]
    # Feature at time t should predict return from t to t+k
    # forward_returns[t] now contains return from t to t+k (future return)
    aligned_feature = feature.values
    aligned_returns = forward_returns.values

    # Drop NaN values (last k bars will have NaN returns due to forward shift)
    # scipy will handle this with nan_policy='omit', but let's be explicit
    valid_mask = ~(np.isnan(aligned_feature) | np.isnan(aligned_returns))
    valid_feature = aligned_feature[valid_mask]
    valid_returns = aligned_returns[valid_mask]

    # Validate sufficient valid data
    if len(valid_feature) < 30:
        raise ValueError(
            f"Insufficient valid data after removing NaNs: "
            f"need at least 30, got {len(valid_feature)}"
        )

    # Calculate Spearman rank correlation
    # This will raise if scipy encounters an error
    correlation, p_value = stats.spearmanr(valid_feature, valid_returns, nan_policy="omit")

    # Validate output is numeric
    if not isinstance(correlation, (int, float, np.number)):
        raise RuntimeError(
            f"scipy.stats.spearmanr returned non-numeric correlation: {correlation}"
        )

    # Return correlation coefficient (ignore p_value for now)
    return float(correlation)


def validate_information_coefficient(
    feature: pd.Series,
    prices: pd.Series,
    forward_periods: int = 1,
    return_type: Literal["simple", "log"] = "log",
    threshold: float = 0.03,
) -> bool:
    """
    Validate feature has sufficient predictive power (IC > threshold).

    Success Gate: IC > 0.03 (SOTA threshold for predictive features)

    Args:
        feature: Feature values at time t
        prices: Price series
        forward_periods: Look-ahead periods for return calculation
        return_type: "simple" or "log" returns
        threshold: Minimum IC threshold (default: 0.03 for SOTA)

    Returns:
        True if IC > threshold (feature has predictive power)

    Raises:
        ValueError: If IC <= threshold (feature fails validation gate)
        TypeError: If inputs have incorrect types (propagated)
        RuntimeError: If scipy fails (propagated)

    Example:
        >>> ic_valid = validate_information_coefficient(feature_values, df['close'])
        >>> assert ic_valid  # IC > 0.03
    """
    # Calculate IC (this may raise)
    ic = calculate_information_coefficient(
        feature=feature,
        prices=prices,
        forward_periods=forward_periods,
        return_type=return_type,
    )

    # Validate against threshold
    if ic <= threshold:
        raise ValueError(
            f"Feature fails IC validation gate!\n"
            f"IC = {ic:.4f} <= threshold {threshold:.4f}\n"
            f"Feature does not have sufficient predictive power for {forward_periods}-step-ahead returns.\n"
            f"SOTA threshold for predictive features: IC > 0.03"
        )

    # IC > threshold → validation passed
    return True
