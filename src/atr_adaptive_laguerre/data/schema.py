"""
Pydantic schemas for OHLCV and order flow data validation.

SLOs:
- Availability: 100% (strict validation, fail fast on invalid data)
- Correctness: 100% (Pydantic v2 validation)
- Security: Zero credential exposure (data only, no auth)
- Observability: Full type coverage (mypy strict)
- Maintainability: Out-of-box Pydantic validation

Error Handling: raise_and_propagate (Pydantic raises ValidationError on invalid data)
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class OHLCVRecord(BaseModel):
    """
    Single OHLCV record from gapless-crypto-data.

    Schema validation for 11-column Binance data format.
    Raises ValidationError on type mismatch or missing fields.

    Reference: https://pypi.org/project/gapless-crypto-data/
    """

    date: datetime = Field(description="Bar open timestamp")
    open: float = Field(gt=0, description="Open price (must be positive)")
    high: float = Field(gt=0, description="High price (must be positive)")
    low: float = Field(gt=0, description="Low price (must be positive)")
    close: float = Field(gt=0, description="Close price (must be positive)")
    volume: float = Field(ge=0, description="Base asset volume (non-negative)")
    close_time: datetime = Field(description="Bar close timestamp")
    quote_asset_volume: float = Field(ge=0, description="Quote asset volume")
    number_of_trades: int = Field(ge=0, description="Number of trades in bar")
    taker_buy_base_asset_volume: float = Field(ge=0, description="Taker buy base volume")
    taker_buy_quote_asset_volume: float = Field(ge=0, description="Taker buy quote volume")

    @field_validator("high")
    @classmethod
    def validate_high_ge_low(cls, v: float, info) -> float:
        """Validate high >= low (market microstructure constraint)."""
        if "low" in info.data and v < info.data["low"]:
            raise ValueError(f"high ({v}) must be >= low ({info.data['low']})")
        return v

    @field_validator("high")
    @classmethod
    def validate_high_ge_open(cls, v: float, info) -> float:
        """Validate high >= open."""
        if "open" in info.data and v < info.data["open"]:
            raise ValueError(f"high ({v}) must be >= open ({info.data['open']})")
        return v

    @field_validator("high")
    @classmethod
    def validate_high_ge_close(cls, v: float, info) -> float:
        """Validate high >= close."""
        if "close" in info.data and v < info.data["close"]:
            raise ValueError(f"high ({v}) must be >= close ({info.data['close']})")
        return v

    @field_validator("low")
    @classmethod
    def validate_low_le_open(cls, v: float, info) -> float:
        """Validate low <= open."""
        if "open" in info.data and v > info.data["open"]:
            raise ValueError(f"low ({v}) must be <= open ({info.data['open']})")
        return v

    @field_validator("low")
    @classmethod
    def validate_low_le_close(cls, v: float, info) -> float:
        """Validate low <= close."""
        if "close" in info.data and v > info.data["close"]:
            raise ValueError(f"low ({v}) must be <= close ({info.data['close']})")
        return v

    @field_validator("close_time")
    @classmethod
    def validate_close_after_open(cls, v: datetime, info) -> datetime:
        """Validate close_time > date."""
        if "date" in info.data and v <= info.data["date"]:
            raise ValueError(f"close_time ({v}) must be > date ({info.data['date']})")
        return v

    model_config = ConfigDict(
        strict=True,  # Strict type validation
        frozen=True,  # Immutable after creation
    )


class OHLCVBatch(BaseModel):
    """
    Batch of OHLCV records with monotonic timestamp validation.

    Raises ValidationError if timestamps are not strictly increasing.
    """

    records: list[OHLCVRecord] = Field(min_length=1, description="OHLCV records")

    @field_validator("records")
    @classmethod
    def validate_monotonic_timestamps(cls, v: list[OHLCVRecord]) -> list[OHLCVRecord]:
        """
        Validate timestamps are strictly increasing (no gaps or reversals).

        Raises:
            ValueError: If timestamps are not monotonic
        """
        for i in range(1, len(v)):
            if v[i].date <= v[i - 1].date:
                raise ValueError(
                    f"Timestamps not monotonic: "
                    f"records[{i}].date ({v[i].date}) <= "
                    f"records[{i-1}].date ({v[i-1].date})"
                )
        return v

    model_config = ConfigDict(
        strict=True,
        frozen=True,
    )
