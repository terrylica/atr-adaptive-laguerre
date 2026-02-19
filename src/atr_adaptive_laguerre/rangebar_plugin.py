"""rangebar-py FeatureProvider plugin for ATR-Adaptive Laguerre RSI.

This module is discovered via the 'rangebar.feature_providers' entry point
when atr-adaptive-laguerre is installed alongside rangebar-py[laguerre].

It is NOT imported by default — only when rangebar-py calls discover_providers().

Issue #1: https://github.com/terrylica/atr-adaptive-laguerre/issues/1
"""

from __future__ import annotations

import logging
import os
from importlib.metadata import version

import numpy as np
import pandas as pd

from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig

logger = logging.getLogger(__name__)

# ---- Default config: curated from Gen800 best performer ----
# These parameters should be the single best Laguerre config from Gen800 sweep.
# Update when Gen800 final rankings are available.
DEFAULT_CONFIG = ATRAdaptiveLaguerreRSIConfig(
    atr_period=14,  # TODO: replace with Gen800 winner
    smoothing_period=3,  # TODO: replace with Gen800 winner
    level_up=0.75,  # TODO: replace with Gen800 winner
    level_down=0.10,  # TODO: replace with Gen800 winner
    adaptive_offset=0.50,  # TODO: replace with Gen800 winner
)

# Column prefix — all columns start with "laguerre_" for namespace isolation
_PREFIX = "laguerre_"

# Curated output columns (6 total — not the full 43 feature set)
_OUTPUT_COLUMNS = (
    "laguerre_rsi",
    "laguerre_regime",
    "laguerre_regime_strength",
    "laguerre_bars_in_regime",
    "laguerre_tail_risk_score",
    "laguerre_rsi_velocity",
)

# Mapping from fit_transform_features() column names to output column names
_FEATURE_MAP = {
    "rsi": "laguerre_rsi",
    "regime": "laguerre_regime",
    "regime_strength": "laguerre_regime_strength",
    "bars_in_regime": "laguerre_bars_in_regime",
    "tail_risk_score": "laguerre_tail_risk_score",
    "rsi_velocity": "laguerre_rsi_velocity",
}


def _load_config_from_env() -> ATRAdaptiveLaguerreRSIConfig | None:
    """Load Laguerre config from RANGEBAR_LAGUERRE_* env vars if set."""
    atr = os.environ.get("RANGEBAR_LAGUERRE_ATR_PERIOD")
    if atr is None:
        return None
    return ATRAdaptiveLaguerreRSIConfig(
        atr_period=int(atr),
        smoothing_period=int(os.environ.get("RANGEBAR_LAGUERRE_SMOOTHING", "3")),
        level_up=float(os.environ.get("RANGEBAR_LAGUERRE_LEVEL_UP", "0.75")),
        level_down=float(os.environ.get("RANGEBAR_LAGUERRE_LEVEL_DOWN", "0.10")),
        adaptive_offset=float(os.environ.get("RANGEBAR_LAGUERRE_ADAPTIVE_OFFSET", "0.50")),
    )


class LaguerreFeatureProvider:
    """FeatureProvider plugin for rangebar-py.

    Computes ATR-Adaptive Laguerre RSI and derived features for each bar,
    using the curated config from Gen800 sweep results.

    Implements the rangebar-py FeatureProvider protocol:
    - name: str
    - version: str
    - columns: tuple[str, ...]
    - min_bars: int
    - enrich(bars_df, symbol, threshold_decimal_bps) -> pd.DataFrame
    """

    def __init__(self, config: ATRAdaptiveLaguerreRSIConfig | None = None):
        self._config = config or _load_config_from_env() or DEFAULT_CONFIG
        self._indicator = ATRAdaptiveLaguerreRSI(self._config)

    @property
    def name(self) -> str:
        return "laguerre"

    @property
    def version(self) -> str:
        return version("atr-adaptive-laguerre")

    @property
    def columns(self) -> tuple[str, ...]:
        return _OUTPUT_COLUMNS

    @property
    def min_bars(self) -> int:
        return self._indicator.min_lookback

    def enrich(
        self,
        bars: pd.DataFrame,
        symbol: str,
        threshold_decimal_bps: int,
    ) -> pd.DataFrame:
        """Add laguerre_* columns to range bar DataFrame.

        Parameters
        ----------
        bars : pd.DataFrame
            Range bars with at minimum: open, high, low, close, volume.
            Index is either RangeIndex or DatetimeIndex.
            Rows are chronologically sorted, single symbol, single threshold.
        symbol : str
            Trading symbol (e.g., "BTCUSDT"). Not used in computation
            but available for config overrides per asset.
        threshold_decimal_bps : int
            Bar threshold. Not used in computation but available for
            config overrides per threshold.

        Returns
        -------
        pd.DataFrame
            Input DataFrame with 6 additional laguerre_* columns appended.
            First min_bars rows will have NaN values (warmup period).
        """
        # Idempotency: skip if already enriched
        if self.columns[0] in bars.columns:
            return bars

        if len(bars) < self.min_bars:
            logger.warning(
                "Only %d bars for %s@%d (need %d for warmup). "
                "All laguerre_* columns will be NaN.",
                len(bars),
                symbol,
                threshold_decimal_bps,
                self.min_bars,
            )
            for col in self.columns:
                bars[col] = np.nan
            return bars

        # Prepare OHLCV input for fit_transform_features()
        ohlcv = bars[["open", "high", "low", "close", "volume"]].copy()

        # Handle datetime: fit_transform_features() needs a 'date' column
        if isinstance(bars.index, pd.DatetimeIndex):
            ohlcv["date"] = bars.index
        elif "timestamp_ms" in bars.columns:
            ohlcv["date"] = pd.to_datetime(bars["timestamp_ms"], unit="ms")
        else:
            # Fallback: synthetic sequential dates (feature computation is timestamp-agnostic)
            ohlcv["date"] = pd.date_range("2020-01-01", periods=len(bars), freq="1s")

        # Compute full feature matrix (43 columns for single-interval)
        features = self._indicator.fit_transform_features(ohlcv)

        # Map curated subset to laguerre_* column names
        for src_col, dst_col in _FEATURE_MAP.items():
            if src_col in features.columns:
                bars[dst_col] = features[src_col].values
            else:
                logger.warning("Expected feature column '%s' not found", src_col)
                bars[dst_col] = np.nan

        return bars
