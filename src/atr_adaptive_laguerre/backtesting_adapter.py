"""
backtesting.py framework adapter for ATR-Adaptive Laguerre RSI indicator.

Pydantic-based API following industry-standard documentation pattern.
Single source of truth: Pydantic models define data contracts, validation, and JSON Schema.

Layer 3: Rich docstrings with typed parameters (Layer 1-2 in backtesting_models.py)

SLO Guarantees:
- Availability: 100% when backtesting.py installed
- Correctness: Column mapping bidirectional accuracy 100%
- Correctness: Pydantic validation on all inputs 100%
- Correctness: Non-anticipative property maintained 100%
- Correctness: Output value range [0.0, 1.0]: 100%
- Correctness: Output length matches input length: 100%
- Observability: JSON Schema generation, clear error messages

Error handling: raise_and_propagate (Pydantic ValidationError, no fallbacks)

Version: 2.0.0 (BREAKING CHANGE from 1.x: requires Pydantic model parameters)
"""

import warnings
from typing import Any, Callable

import numpy as np
import pandas as pd

from atr_adaptive_laguerre.backtesting_models import FeatureConfig, IndicatorConfig
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
    rename_dict = {k: v for k, v in COLUMN_MAPPING.items() if k in df.columns}
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


def compute_indicator(config: IndicatorConfig, data: Any) -> np.ndarray:
    """
    Compute ATR-Adaptive Laguerre RSI indicator for backtesting.py Strategy.I().

    Non-anticipative volatility-adaptive momentum indicator combining
    True Range, ATR, adaptive coefficient, Laguerre filter, and RSI calculation.

    Args:
        config: Validated IndicatorConfig with parameters
            Use IndicatorConfig() to create with Pydantic validation
        data: backtesting.py data object (with .df accessor) or pd.DataFrame
            Must have Title case columns: Open, High, Low, Close, Volume

    Returns:
        np.ndarray of RSI values in range [0.0, 1.0], length matches input

    Raises:
        ValidationError: If config parameters invalid (raised by Pydantic)
        TypeError: If data is invalid type
        ValueError: If required columns are missing

    Examples:
        >>> from atr_adaptive_laguerre import IndicatorConfig, compute_indicator
        >>>
        >>> # Basic usage with defaults
        >>> config = IndicatorConfig()
        >>> class MyStrategy(Strategy):
        ...     def init(self):
        ...         self.rsi = self.I(compute_indicator, config, self.data)
        ...     def next(self):
        ...         if self.rsi[-1] < 0.15:
        ...             self.buy()
        ...         elif self.rsi[-1] > 0.85:
        ...             self.position.close()
        >>>
        >>> # Custom parameters with validation
        >>> config = IndicatorConfig(atr_period=20, smoothing_period=7)
        >>> class MyStrategy(Strategy):
        ...     def init(self):
        ...         self.rsi = self.I(compute_indicator, config, self.data)

    See Also:
        IndicatorConfig: Configuration model with parameter validation
        FeatureConfig: For accessing extended features (31 total)
        compute_feature: Extract single feature from expansion
    """
    df = _convert_data_to_dataframe(data)

    internal_config = ATRAdaptiveLaguerreRSIConfig.single_interval(
        atr_period=config.atr_period,
        smoothing_period=config.smoothing_period,
        adaptive_offset=config.adaptive_offset,
        level_up=config.level_up,
        level_down=config.level_down,
    )

    # Suppress single-interval mode warning (intentional for backtesting.py adapter)
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message="Using single-interval mode")
        indicator = ATRAdaptiveLaguerreRSI(internal_config)
        rsi_series = indicator.fit_transform(df)

    return rsi_series.values


def compute_feature(config: FeatureConfig, data: Any) -> np.ndarray:
    """
    Extract single feature from 31-feature expansion for backtesting.py.

    Provides access to extended features: regime classification, thresholds,
    crossings, temporal metrics, rate of change, statistics, tail risk.

    Args:
        config: Validated FeatureConfig with feature_name and parameters
            Use FeatureConfig(feature_name='regime') to select feature
        data: backtesting.py data object or pd.DataFrame

    Returns:
        np.ndarray of feature values, length matches input

    Raises:
        ValidationError: If config parameters invalid (raised by Pydantic)
        TypeError: If data is invalid type
        ValueError: If required columns are missing or feature_name invalid

    Examples:
        >>> from atr_adaptive_laguerre import FeatureConfig, compute_feature
        >>>
        >>> # Extract regime classification
        >>> regime_config = FeatureConfig(feature_name='regime')
        >>> class MyStrategy(Strategy):
        ...     def init(self):
        ...         self.regime = self.I(compute_feature, regime_config, self.data)
        ...         self.volatility = self.I(
        ...             compute_feature,
        ...             FeatureConfig(feature_name='rsi_volatility_20'),
        ...             self.data
        ...         )
        ...     def next(self):
        ...         if self.regime[-1] == 0:  # Bearish
        ...             # Avoid trading
        ...             pass
        >>>
        >>> # Get list of all available features
        >>> FeatureConfig.supported_features()
        ['rsi', 'regime', 'regime_bearish', ...]

    See Also:
        FeatureConfig: Configuration with 31 available features
        FeatureConfig.supported_features(): List all valid feature names
        IndicatorConfig: For basic RSI indicator only
    """
    df = _convert_data_to_dataframe(data)

    internal_config = ATRAdaptiveLaguerreRSIConfig.single_interval(
        atr_period=config.atr_period,
        smoothing_period=config.smoothing_period,
        adaptive_offset=config.adaptive_offset,
        level_up=config.level_up,
        level_down=config.level_down,
    )

    # Suppress single-interval mode warning (intentional for backtesting.py adapter)
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", message="Using single-interval mode")
        indicator = ATRAdaptiveLaguerreRSI(internal_config)
        features_df = indicator.fit_transform_features(df)

    if config.feature_name not in features_df.columns:
        available_features = sorted(features_df.columns.tolist())
        raise ValueError(
            f"Feature '{config.feature_name}' not found. "
            f"Available features ({len(available_features)}): {available_features}"
        )

    return features_df[config.feature_name].values


def make_indicator(
    atr_period: int = 14,
    smoothing_period: int = 5,
    adaptive_offset: float = 0.75,
    level_up: float = 0.85,
    level_down: float = 0.15,
) -> Callable[[Any], np.ndarray]:
    """
    Factory function to create configured indicator with Pydantic validation.

    Creates closure that captures validated IndicatorConfig for use with Strategy.I().
    Parameters validated at factory call time, not at indicator execution time.

    Args:
        atr_period: ATR lookback period (range: 10-30, default: 14)
        smoothing_period: Price smoothing period (range: 3-10, default: 5)
        adaptive_offset: Adaptive period offset (range: 0.0-1.0, default: 0.75)
        level_up: Upper threshold (range: 0.5-1.0, default: 0.85)
        level_down: Lower threshold (range: 0.0-0.5, default: 0.15)

    Returns:
        Callable that accepts data and returns np.ndarray

    Raises:
        ValidationError: If any parameter outside valid range (raised by Pydantic)

    Examples:
        >>> from atr_adaptive_laguerre import make_indicator
        >>>
        >>> # Create fast and slow RSI indicators
        >>> fast_rsi = make_indicator(atr_period=10, smoothing_period=3)
        >>> slow_rsi = make_indicator(atr_period=20, smoothing_period=7)
        >>>
        >>> class DualRSIStrategy(Strategy):
        ...     def init(self):
        ...         self.fast = self.I(fast_rsi, self.data)
        ...         self.slow = self.I(slow_rsi, self.data)
        ...     def next(self):
        ...         if self.fast[-1] > self.slow[-1]:
        ...             # Fast RSI crossed above slow
        ...             self.buy()
        ...         elif self.fast[-1] < self.slow[-1]:
        ...             # Fast RSI crossed below slow
        ...             if self.position:
        ...                 self.position.close()
        >>>
        >>> # Validation catches invalid parameters
        >>> invalid = make_indicator(atr_period=50)  # Raises ValidationError

    See Also:
        IndicatorConfig: Underlying configuration model
        compute_indicator: Direct function using IndicatorConfig
    """
    # Pydantic validation happens here at factory creation time
    config = IndicatorConfig(
        atr_period=atr_period,
        smoothing_period=smoothing_period,
        adaptive_offset=adaptive_offset,
        level_up=level_up,
        level_down=level_down,
    )

    def indicator(data: Any) -> np.ndarray:
        return compute_indicator(config, data)

    # Set function name for backtesting.py plot legends
    indicator.__name__ = f"ATR_Laguerre_{atr_period}_{smoothing_period}"

    return indicator
