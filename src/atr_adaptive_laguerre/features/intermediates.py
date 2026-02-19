"""Intermediate values from the ATR-Adaptive Laguerre RSI computation pipeline.

These values are computed during fit_transform() but were previously discarded.
Now captured as numpy arrays for use as additional features by FeatureExpander.

Non-anticipative guarantee: All values at index i use only data from bars 0..i.
"""

from dataclasses import dataclass

import numpy as np


@dataclass
class IntermediateValues:
    """Per-bar intermediate values from the core computation loop.

    Each field is a 1D numpy array of length n_bars, aligned with the input DataFrame index.

    Attributes:
        adaptive_coeff: Adaptive coefficient [0,1] per bar
        gamma: Laguerre gamma value (0,1) per bar
        L0: Laguerre filter stage 0 (price-scale)
        L1: Laguerre filter stage 1 (price-scale)
        L2: Laguerre filter stage 2 (price-scale)
        L3: Laguerre filter stage 3 (price-scale)
        min_atr: Minimum ATR in lookback window per bar
        max_atr: Maximum ATR in lookback window per bar
        atr: Current ATR value per bar
        close: Close prices (for Kaufman Efficiency Ratio)
    """

    adaptive_coeff: np.ndarray
    gamma: np.ndarray
    L0: np.ndarray
    L1: np.ndarray
    L2: np.ndarray
    L3: np.ndarray
    min_atr: np.ndarray
    max_atr: np.ndarray
    atr: np.ndarray
    close: np.ndarray
