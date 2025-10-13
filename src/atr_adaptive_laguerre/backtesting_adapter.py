"""
backtesting.py framework adapter for ATR-Adaptive Laguerre RSI indicator.

Exposes package as indicator for backtesting.py Strategy.I() integration.
Column mapping: Title case (backtesting.py) ↔ lowercase (package internal).
Error handling: strict propagation, no fallbacks or silent failures.

SLO Guarantees:
- Availability: 100% when backtesting.py installed
- Correctness: Column mapping bidirectional accuracy 100%
- Correctness: Non-anticipative property maintained 100%
- Correctness: Output value range [0.0, 1.0]: 100%
- Correctness: Output length matches input length: 100%
- Observability: Clear error messages for all failure modes

Version: 1.1.0
"""

import warnings
from typing import Any, Callable

import numpy as np
import pandas as pd

from atr_adaptive_laguerre.features.atr_adaptive_rsi import (
    ATRAdaptiveLaguerreRSI,
    ATRAdaptiveLaguerreRSIConfig,
)

# Column mapping: backtesting.py (Title case) → package (lowercase)
COLUMN_MAPPING = {
    "Open": "open",
    "High": "high",
    "Low": "low",
    "Close": "close",
    "Volume": "volume",
}

# Required columns for OHLCV computation
REQUIRED_COLUMNS = ["open", "high", "low", "close", "volume"]


def _convert_data_to_dataframe(data: Any) -> pd.DataFrame:
    """
    Convert backtesting.py data object to DataFrame with lowercase columns.

    Args:
        data: backtesting.py data object (with .df accessor) or pd.DataFrame

    Returns:
        DataFrame with lowercase OHLCV columns

    Raises:
        TypeError: If data is not backtesting.py data object or DataFrame
        ValueError: If required columns are missing
    """
    # Extract DataFrame from data object or use directly
    if hasattr(data, "df"):
        df = data.df.copy()
    elif isinstance(data, pd.DataFrame):
        df = data.copy()
    else:
        raise TypeError(
            f"data must be backtesting.py data object or pd.DataFrame, "
            f"got {type(data).__name__}"
        )

    # Rename columns from Title case to lowercase
    rename_dict = {
        k: v for k, v in COLUMN_MAPPING.items() if k in df.columns
    }
    df = df.rename(columns=rename_dict)

    # Validate required columns exist
    missing_columns = set(REQUIRED_COLUMNS) - set(df.columns)
    if missing_columns:
        available_columns = list(df.columns)
        raise ValueError(
            f"Data missing required columns: {sorted(missing_columns)}. "
            f"Available columns: {available_columns}. "
            f"Expected Title case: {list(COLUMN_MAPPING.keys())}"
        )

    return df


def atr_laguerre_indicator(
    data: Any,
    atr_period: int = 14,
    smoothing_period: int = 5,
    adaptive_offset: float = 0.75,
    level_up: float = 0.85,
    level_down: float = 0.15,
) -> np.ndarray:
    """
    ATR-Adaptive Laguerre RSI indicator for backtesting.py Strategy.I().

    Non-anticipative volatility-adaptive momentum indicator combining
    True Range, ATR, adaptive coefficient, Laguerre filter, and RSI.

    Args:
        data: backtesting.py data object (with .df accessor) or pd.DataFrame
            Must have Title case columns: Open, High, Low, Close, Volume
        atr_period: ATR lookback period (default: 14)
        smoothing_period: Price smoothing period (default: 5)
        adaptive_offset: Adaptive period offset coefficient (default: 0.75)
        level_up: Upper threshold for signals (default: 0.85)
        level_down: Lower threshold for signals (default: 0.15)

    Returns:
        np.ndarray of RSI values in range [0.0, 1.0], length matches input

    Raises:
        TypeError: If data is invalid type
        ValueError: If required columns are missing

    Example:
        >>> class MyStrategy(Strategy):
        ...     def init(self):
        ...         self.rsi = self.I(atr_laguerre_indicator, self.data)
        ...
        ...     def next(self):
        ...         if self.rsi[-1] < 0.15:
        ...             self.buy()
        ...         elif self.rsi[-1] > 0.85:
        ...             self.position.close()
    """
    df = _convert_data_to_dataframe(data)

    config = ATRAdaptiveLaguerreRSIConfig.single_interval(
        atr_period=atr_period,
        smoothing_period=smoothing_period,
        adaptive_offset=adaptive_offset,
        level_up=level_up,
        level_down=level_down,
    )

    # Suppress single-interval mode warning (intentional for backtesting.py adapter)
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message="Using single-interval mode")
        indicator = ATRAdaptiveLaguerreRSI(config)
        rsi_series = indicator.fit_transform(df)

    return rsi_series.values


def atr_laguerre_features(
    data: Any,
    feature_name: str = "rsi",
    atr_period: int = 14,
    smoothing_period: int = 5,
    adaptive_offset: float = 0.75,
    level_up: float = 0.85,
    level_down: float = 0.15,
) -> np.ndarray:
    """
    Extract single feature from 31-feature expansion for backtesting.py.

    Provides access to extended features: regime classification, thresholds,
    crossings, temporal metrics, rate of change, statistics, tail risk.

    Args:
        data: backtesting.py data object or pd.DataFrame
        feature_name: Feature to extract (default: 'rsi')
            Available: 'rsi', 'regime', 'regime_strength', 'dist_overbought',
            'dist_oversold', 'rsi_velocity', 'rsi_volatility_20', etc.
        atr_period: ATR lookback period (default: 14)
        smoothing_period: Price smoothing period (default: 5)
        adaptive_offset: Adaptive period offset (default: 0.75)
        level_up: Upper threshold (default: 0.85)
        level_down: Lower threshold (default: 0.15)

    Returns:
        np.ndarray of feature values, length matches input

    Raises:
        TypeError: If data is invalid type
        ValueError: If required columns are missing or feature_name invalid

    Example:
        >>> class MyStrategy(Strategy):
        ...     def init(self):
        ...         self.regime = self.I(
        ...             atr_laguerre_features,
        ...             self.data,
        ...             feature_name='regime'
        ...         )
        ...         self.volatility = self.I(
        ...             atr_laguerre_features,
        ...             self.data,
        ...             feature_name='rsi_volatility_20'
        ...         )

    Available Features:
        Base: rsi
        Regimes: regime, regime_bearish, regime_neutral, regime_bullish,
                regime_changed, bars_in_regime, regime_strength
        Thresholds: dist_overbought, dist_oversold, dist_midline,
                   abs_dist_overbought, abs_dist_oversold
        Crossings: cross_above_oversold, cross_below_overbought,
                  cross_above_midline, cross_below_midline
        Temporal: bars_since_oversold, bars_since_overbought, bars_since_extreme
        Rate of change: rsi_change_1, rsi_change_5, rsi_velocity
        Statistics: rsi_percentile_20, rsi_zscore_20, rsi_volatility_20,
                   rsi_range_20
        Tail risk: rsi_shock_1bar, extreme_regime_persistence,
                  rsi_volatility_spike, tail_risk_score
    """
    df = _convert_data_to_dataframe(data)

    config = ATRAdaptiveLaguerreRSIConfig.single_interval(
        atr_period=atr_period,
        smoothing_period=smoothing_period,
        adaptive_offset=adaptive_offset,
        level_up=level_up,
        level_down=level_down,
    )

    # Suppress single-interval mode warning (intentional for backtesting.py adapter)
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message="Using single-interval mode")
        indicator = ATRAdaptiveLaguerreRSI(config)
        features_df = indicator.fit_transform_features(df)

    if feature_name not in features_df.columns:
        available_features = sorted(features_df.columns.tolist())
        raise ValueError(
            f"Feature '{feature_name}' not found. "
            f"Available features ({len(available_features)}): {available_features}"
        )

    return features_df[feature_name].values


def make_atr_laguerre_indicator(
    atr_period: int = 14,
    smoothing_period: int = 5,
    adaptive_offset: float = 0.75,
    level_up: float = 0.85,
    level_down: float = 0.15,
) -> Callable[[Any], np.ndarray]:
    """
    Factory function to create configured indicator function.

    Creates closure with captured parameters for use with Strategy.I().
    Useful for multiple indicators with different configurations.

    Args:
        atr_period: ATR lookback period (default: 14)
        smoothing_period: Price smoothing period (default: 5)
        adaptive_offset: Adaptive period offset (default: 0.75)
        level_up: Upper threshold (default: 0.85)
        level_down: Lower threshold (default: 0.15)

    Returns:
        Callable that accepts data and returns np.ndarray

    Example:
        >>> fast_rsi = make_atr_laguerre_indicator(atr_period=10, smoothing_period=3)
        >>> slow_rsi = make_atr_laguerre_indicator(atr_period=20, smoothing_period=7)
        >>>
        >>> class MyStrategy(Strategy):
        ...     def init(self):
        ...         self.fast = self.I(fast_rsi, self.data)
        ...         self.slow = self.I(slow_rsi, self.data)
        ...
        ...     def next(self):
        ...         if self.fast[-1] > self.slow[-1]:
        ...             self.buy()
    """

    def indicator(data: Any) -> np.ndarray:
        return atr_laguerre_indicator(
            data,
            atr_period=atr_period,
            smoothing_period=smoothing_period,
            adaptive_offset=adaptive_offset,
            level_up=level_up,
            level_down=level_down,
        )

    # Set function name for backtesting.py plot legends
    indicator.__name__ = f"ATR_Laguerre_{atr_period}_{smoothing_period}"

    return indicator
