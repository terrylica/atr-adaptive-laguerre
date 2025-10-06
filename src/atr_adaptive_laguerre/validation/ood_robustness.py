"""
Out-of-Distribution (OOD) robustness validation for feature constructors.

SLOs:
- Availability: 100% (pure computation, no external dependencies)
- Correctness: 100% (statistical regime detection + IC validation)
- Security: N/A (validation only)
- Observability: Full type hints (mypy strict)
- Maintainability: High (standard statistical methods)

Error Handling: raise_and_propagate
- ValueError on insufficient regime separation or IC degradation
- TypeError on incorrect input types
- All errors propagated (no handling)

Methodology:
- Split data into regimes (high/low volatility, trending/ranging, bull/bear)
- Validate feature maintains IC > threshold across all regimes
- Ensures feature generalizes to unseen market conditions
"""

from typing import Callable, Literal

import numpy as np
import pandas as pd

from atr_adaptive_laguerre.validation.information_coefficient import (
    calculate_information_coefficient,
)


def split_by_volatility(
    df: pd.DataFrame, quantile: float = 0.5
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """
    Split OHLCV data into high/low volatility regimes.

    Volatility proxy: ATR (Average True Range) over trailing 20-bar window.

    Args:
        df: OHLCV DataFrame with columns: high, low, close
        quantile: Split quantile (default: 0.5 for median split)
                 0.5 → equal-sized high/low regimes

    Returns:
        Tuple of (low_vol_df, high_vol_df)

    Raises:
        ValueError: If insufficient data or missing columns
        TypeError: If df not DataFrame
    """
    if not isinstance(df, pd.DataFrame):
        raise TypeError(f"df must be pd.DataFrame, got {type(df)}")

    required_cols = ["high", "low", "close"]
    missing = set(required_cols) - set(df.columns)
    if missing:
        raise ValueError(f"df missing required columns: {missing}")

    if len(df) < 50:
        raise ValueError(f"Insufficient data for regime split: need >= 50, got {len(df)}")

    # Calculate True Range
    high = df["high"].values
    low = df["low"].values
    close = df["close"].values

    tr = np.zeros(len(df))
    tr[0] = high[0] - low[0]
    for i in range(1, len(df)):
        high_val = max(high[i], close[i - 1])
        low_val = min(low[i], close[i - 1])
        tr[i] = high_val - low_val

    # Calculate rolling ATR (20-bar window)
    atr = pd.Series(tr).rolling(window=20).mean().values

    # Split by volatility quantile
    threshold = np.nanquantile(atr, quantile)
    low_vol_mask = atr <= threshold
    high_vol_mask = atr > threshold

    low_vol_df = df[low_vol_mask].copy()
    high_vol_df = df[high_vol_mask].copy()

    return low_vol_df, high_vol_df


def split_by_trend(
    df: pd.DataFrame, lookback: int = 50, quantile: float = 0.5
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """
    Split OHLCV data into trending/ranging regimes.

    Trend proxy: Linear regression slope of close prices over lookback window.

    Args:
        df: OHLCV DataFrame with column: close
        lookback: Lookback window for trend calculation (default: 50)
        quantile: Split quantile (default: 0.5 for median split)

    Returns:
        Tuple of (ranging_df, trending_df)

    Raises:
        ValueError: If insufficient data or missing columns
        TypeError: If df not DataFrame
    """
    if not isinstance(df, pd.DataFrame):
        raise TypeError(f"df must be pd.DataFrame, got {type(df)}")

    if "close" not in df.columns:
        raise ValueError("df missing required column: close")

    if len(df) < lookback + 50:
        raise ValueError(
            f"Insufficient data for trend split: need >= {lookback + 50}, got {len(df)}"
        )

    # Calculate rolling linear regression slope
    close = df["close"].values
    slopes = np.zeros(len(df))

    for i in range(lookback, len(df)):
        window = close[i - lookback : i]
        x = np.arange(lookback)
        # Simple linear regression: slope = cov(x, y) / var(x)
        slope = np.cov(x, window)[0, 1] / np.var(x)
        slopes[i] = abs(slope)  # Use absolute slope for trending strength

    # Split by trend strength quantile
    threshold = np.quantile(slopes[lookback:], quantile)
    ranging_mask = slopes <= threshold
    trending_mask = slopes > threshold

    ranging_df = df[ranging_mask].copy()
    trending_df = df[trending_mask].copy()

    return ranging_df, trending_df


def validate_ood_robustness(
    feature_fn: Callable[[pd.DataFrame], pd.Series],
    df: pd.DataFrame,
    regime_type: Literal["volatility", "trend"] = "volatility",
    ic_threshold: float = 0.03,
    ic_degradation_threshold: float = 0.02,
) -> dict[str, float]:
    """
    Validate feature maintains predictive power across OOD regimes.

    Test methodology:
    1. Split data into two regimes (high/low vol OR trending/ranging)
    2. Compute feature + IC on each regime independently
    3. Validate IC > threshold on both regimes
    4. Validate IC degradation < degradation_threshold between regimes

    Success criteria:
    - IC_regime1 > ic_threshold (e.g., 0.03)
    - IC_regime2 > ic_threshold (e.g., 0.03)
    - |IC_regime1 - IC_regime2| < ic_degradation_threshold (e.g., 0.02)

    Args:
        feature_fn: Feature computation function (df → Series)
        df: OHLCV DataFrame with required columns
        regime_type: "volatility" for high/low vol split
                    "trend" for trending/ranging split
        ic_threshold: Minimum IC per regime (default: 0.03)
        ic_degradation_threshold: Max IC drop between regimes (default: 0.02)

    Returns:
        Dict with IC values per regime:
        {
            "regime1_ic": float,
            "regime2_ic": float,
            "ic_degradation": float,
            "regime1_name": str,
            "regime2_name": str
        }

    Raises:
        ValueError: If feature fails OOD validation (IC too low or degradation too high)
        TypeError: If inputs have incorrect types
        RuntimeError: If feature_fn or IC calculation fails (propagated)

    Example:
        >>> from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI
        >>> feature = ATRAdaptiveLaguerreRSI()
        >>> df = load_ohlcv_data()
        >>> result = validate_ood_robustness(feature.fit_transform, df, regime_type="volatility")
        >>> assert result["regime1_ic"] > 0.03
        >>> assert result["regime2_ic"] > 0.03
        >>> assert result["ic_degradation"] < 0.02
    """
    # Validate inputs
    if not callable(feature_fn):
        raise TypeError(f"feature_fn must be callable, got {type(feature_fn)}")

    if not isinstance(df, pd.DataFrame):
        raise TypeError(f"df must be pd.DataFrame, got {type(df)}")

    if regime_type not in ("volatility", "trend"):
        raise ValueError(f"regime_type must be 'volatility' or 'trend', got {regime_type}")

    # Split into regimes
    if regime_type == "volatility":
        regime1_df, regime2_df = split_by_volatility(df)
        regime1_name = "low_volatility"
        regime2_name = "high_volatility"
    else:
        regime1_df, regime2_df = split_by_trend(df)
        regime1_name = "ranging"
        regime2_name = "trending"

    # Validate sufficient data per regime
    if len(regime1_df) < 50:
        raise ValueError(
            f"Insufficient {regime1_name} data: need >= 50, got {len(regime1_df)}"
        )
    if len(regime2_df) < 50:
        raise ValueError(
            f"Insufficient {regime2_name} data: need >= 50, got {len(regime2_df)}"
        )

    # Compute feature on each regime
    feature1 = feature_fn(regime1_df)
    feature2 = feature_fn(regime2_df)

    # Validate feature output
    if not isinstance(feature1, pd.Series):
        raise TypeError(f"feature_fn must return pd.Series, got {type(feature1)}")
    if not isinstance(feature2, pd.Series):
        raise TypeError(f"feature_fn must return pd.Series, got {type(feature2)}")

    # Extract prices for IC calculation
    if "close" not in regime1_df.columns:
        raise ValueError("df missing required column: close")

    prices1 = regime1_df["close"]
    prices2 = regime2_df["close"]

    # Calculate IC on each regime (this may raise)
    ic1 = calculate_information_coefficient(feature1, prices1, forward_periods=1)
    ic2 = calculate_information_coefficient(feature2, prices2, forward_periods=1)

    # Calculate IC degradation
    ic_degradation = abs(ic1 - ic2)

    # Validate IC thresholds
    if ic1 < ic_threshold:
        raise ValueError(
            f"Feature fails OOD validation on {regime1_name} regime!\n"
            f"IC = {ic1:.4f} < threshold {ic_threshold:.4f}\n"
            f"Feature does not generalize to {regime1_name} market conditions."
        )

    if ic2 < ic_threshold:
        raise ValueError(
            f"Feature fails OOD validation on {regime2_name} regime!\n"
            f"IC = {ic2:.4f} < threshold {ic_threshold:.4f}\n"
            f"Feature does not generalize to {regime2_name} market conditions."
        )

    # Validate IC stability (degradation threshold)
    if ic_degradation > ic_degradation_threshold:
        raise ValueError(
            f"Feature fails OOD validation due to IC degradation!\n"
            f"IC degradation = {ic_degradation:.4f} > threshold {ic_degradation_threshold:.4f}\n"
            f"{regime1_name} IC = {ic1:.4f}\n"
            f"{regime2_name} IC = {ic2:.4f}\n"
            f"Feature performance is not stable across regimes."
        )

    # All validations passed
    return {
        "regime1_ic": ic1,
        "regime2_ic": ic2,
        "ic_degradation": ic_degradation,
        "regime1_name": regime1_name,
        "regime2_name": regime2_name,
    }
