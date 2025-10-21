"""Data adapters for OHLCV sources."""

try:
    from atr_adaptive_laguerre.data.binance_adapter import BinanceAdapter
    _has_data_extras = True
except ImportError:
    BinanceAdapter = None  # noqa: F841
    _has_data_extras = False

from atr_adaptive_laguerre.data.schema import OHLCVBatch, OHLCVRecord

__all__ = (
    (["BinanceAdapter"] if _has_data_extras else [])
    + [
        "OHLCVRecord",
        "OHLCVBatch",
    ]
)
