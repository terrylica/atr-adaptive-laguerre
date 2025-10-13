"""
Base feature interface for non-anticipative feature engineering.

SLOs:
- Availability: 100% (interface definition, no runtime dependencies)
- Correctness: 100% (ABC contract enforcement)
- Security: N/A (interface only)
- Observability: Full type hints (mypy strict)
- Maintainability: Standard ABC pattern (out-of-box)

Error Handling: raise_and_propagate (AbstractMethod raises TypeError)
"""

from abc import ABC, abstractmethod

import pandas as pd
from pydantic import BaseModel, ConfigDict


class FeatureConfig(BaseModel):
    """
    Base configuration for features.

    All feature configurations must inherit from this class.
    Uses Pydantic for validation with strict mode.
    """

    model_config = ConfigDict(
        strict=True,
        frozen=True,  # Immutable after creation
    )


class BaseFeature(ABC):
    """
    Abstract base class for non-anticipative feature constructors.

    Guarantees:
    - Non-anticipative: Features computed only from i-1 lookback data
    - Stateless transform: fit_transform() is deterministic
    - Type safe: Full mypy coverage

    SLO Contracts:
    - Correctness: Implementations must guarantee non-anticipative property
    - Observability: Implementations must provide type hints
    - Maintainability: Implementations must document MQL5 reference mapping

    Raises:
        TypeError: If subclass doesn't implement abstract methods
        ValueError: If invalid data passed to transform
    """

    def __init__(self, config: FeatureConfig):
        """
        Initialize feature with configuration.

        Args:
            config: Feature configuration (Pydantic validated)

        Raises:
            ValidationError: If config validation fails (propagated from Pydantic)
        """
        self.config = config

    @abstractmethod
    def fit_transform(self, df: pd.DataFrame) -> pd.Series:
        """
        Transform OHLCV data to feature values.

        Must be non-anticipative: only use i-1 lookback data.
        Must be deterministic: same input → same output.

        Args:
            df: OHLCV DataFrame with columns: date, open, high, low, close, volume

        Returns:
            Feature values as pd.Series with same index as df

        Raises:
            ValueError: If df schema invalid (must propagate, not handle)
            TypeError: If df not pd.DataFrame (must propagate, not handle)

        Note:
            Implementations must NOT catch exceptions and provide defaults.
            All errors must propagate to caller for debugging.
        """
        raise NotImplementedError

    @abstractmethod
    def validate_non_anticipative(self, df: pd.DataFrame, n_shuffles: int = 100) -> bool:
        """
        Validate feature is non-anticipative via future data shuffling.

        Args:
            df: Test DataFrame
            n_shuffles: Number of shuffle iterations

        Returns:
            True if feature is non-anticipative

        Raises:
            ValueError: If feature shows lookahead bias
        """
        raise NotImplementedError
