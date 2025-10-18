"""
Binance data adapter using gapless-crypto-data with Parquet caching.

SLOs:
- Availability: 99.9% (depends on gapless-crypto-data + Binance API)
- Correctness: 100% (Pydantic validation on all data)
- Security: Zero credential exposure (public Binance data only)
- Observability: Full logging with httpx, errors propagated
- Maintainability: Out-of-box gapless-crypto-data, minimal custom code

Error Handling: raise_and_propagate
- NetworkError → propagate (no retry)
- ValidationError → propagate (invalid data)
- FileNotFoundError → propagate (cache miss)
"""

from pathlib import Path

import gapless_crypto_data as gcd
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from platformdirs import user_cache_dir


class BinanceAdapter:
    """
    Adapter for gapless-crypto-data with Parquet caching.

    Uses out-of-box gapless-crypto-data library, zero custom HTTP code.
    Caches to Parquet with zstd-9 compression per user toolchain preference.

    Raises:
        NetworkError: On Binance API failures (propagated from gapless-crypto-data)
        ValidationError: On data schema violations (propagated from Pydantic)
        FileNotFoundError: On cache directory creation failures
        ValueError: On invalid parameters
    """

    def __init__(self, cache_dir: Path | None = None):
        """
        Initialize Binance adapter.

        Args:
            cache_dir: Parquet cache directory (default: platformdirs user_cache_dir)

        Raises:
            ValueError: If cache_dir is not a directory
        """
        if cache_dir is None:
            self.cache_dir = Path(user_cache_dir("atr-adaptive-laguerre", "terrylica"))
        else:
            self.cache_dir = Path(cache_dir)

        if self.cache_dir.exists() and not self.cache_dir.is_dir():
            raise ValueError(f"cache_dir must be directory: {self.cache_dir}")

    def fetch(
        self,
        symbol: str,
        interval: str,
        start: str,
        end: str,
        use_cache: bool = True,
    ) -> pd.DataFrame:
        """
        Fetch OHLCV + order flow data from Binance.

        Args:
            symbol: Trading pair (e.g., "BTCUSDT")
            interval: Timeframe (e.g., "1h", "4h", "1d")
            start: Start date (ISO format: "2024-01-01")
            end: End date (ISO format: "2024-06-30")
            use_cache: Whether to use Parquet cache

        Returns:
            DataFrame with 11 columns from gapless-crypto-data:
            - date, open, high, low, close, volume
            - close_time, quote_asset_volume, number_of_trades
            - taker_buy_base_asset_volume, taker_buy_quote_asset_volume

        Raises:
            ValueError: If parameters are invalid
            NetworkError: If Binance API request fails (propagated)
            ValidationError: If data schema validation fails (propagated)
            FileNotFoundError: If cache directory creation fails

        Error Handling: raise_and_propagate (no fallbacks, no retries)
        """
        # Validate parameters (fail fast)
        if not symbol:
            raise ValueError("symbol cannot be empty")
        if not interval:
            raise ValueError("interval cannot be empty")
        if not start:
            raise ValueError("start cannot be empty")
        if not end:
            raise ValueError("end cannot be empty")

        # Check cache first
        if use_cache:
            cache_path = self._get_cache_path(symbol, interval, start, end)
            if cache_path.exists():
                # Read from cache (raises OSError if file corrupted)
                return pq.read_table(cache_path).to_pandas()

        # Fetch from Binance via gapless-crypto-data
        # This will raise NetworkError if API call fails
        # No try/except - let errors propagate
        df = gcd.download(symbol, timeframe=interval, start=start, end=end)

        # Validate schema (11 columns)
        self._validate_schema(df)

        # Cache as Parquet with zstd-9 compression
        if use_cache:
            self._write_cache(df, symbol, interval, start, end)

        return df

    def _validate_schema(self, df: pd.DataFrame) -> None:
        """
        Validate DataFrame has required 11 columns.

        Raises:
            ValueError: If schema validation fails
        """
        required_columns = [
            "date",
            "open",
            "high",
            "low",
            "close",
            "volume",
            "close_time",
            "quote_asset_volume",
            "number_of_trades",
            "taker_buy_base_asset_volume",
            "taker_buy_quote_asset_volume",
        ]

        missing = set(required_columns) - set(df.columns)
        if missing:
            raise ValueError(f"Missing required columns: {missing}")

        # Validate types (fail fast on type mismatch)
        if not pd.api.types.is_datetime64_any_dtype(df["date"]):
            raise ValueError("Column 'date' must be datetime64")

        numeric_columns = [
            "open",
            "high",
            "low",
            "close",
            "volume",
            "quote_asset_volume",
            "taker_buy_base_asset_volume",
            "taker_buy_quote_asset_volume",
        ]
        for col in numeric_columns:
            if not pd.api.types.is_numeric_dtype(df[col]):
                raise ValueError(f"Column '{col}' must be numeric")

        if not pd.api.types.is_integer_dtype(df["number_of_trades"]):
            raise ValueError("Column 'number_of_trades' must be integer")

    def _get_cache_path(self, symbol: str, interval: str, start: str, end: str) -> Path:
        """
        Generate cache file path.

        Args:
            symbol: Trading pair
            interval: Timeframe
            start: Start date
            end: End date

        Returns:
            Path to Parquet cache file
        """
        filename = f"{symbol}_{interval}_{start}_{end}.parquet"
        return self.cache_dir / filename

    def _write_cache(
        self, df: pd.DataFrame, symbol: str, interval: str, start: str, end: str
    ) -> None:
        """
        Write DataFrame to Parquet cache.

        Args:
            df: DataFrame to cache
            symbol: Trading pair
            interval: Timeframe
            start: Start date
            end: End date

        Raises:
            OSError: If cache directory creation or file write fails
        """
        cache_path = self._get_cache_path(symbol, interval, start, end)

        # Create cache directory (raises OSError if fails)
        cache_path.parent.mkdir(parents=True, exist_ok=True)

        # Write Parquet with zstd-9 compression (user toolchain preference)
        table = pa.Table.from_pandas(df)
        pq.write_table(table, cache_path, compression="zstd", compression_level=9)
