"""
ExnessPhase7Adapter: Extract session features from exness-data-preprocess.

Provides integration between exness-data-preprocess (Phase7 30-column schema)
and atr-adaptive-laguerre feature extraction pipeline.

Current Implementation:
- Tier 2: Global Session Flags (3 features)
  * is_nyse_session: US trading hours (09:30-16:00 ET)
  * is_lse_session: London trading hours (08:00-16:30 GMT)
  * is_xtks_session: Tokyo trading hours (09:00-15:00 JST)

Future Tiers (not yet implemented):
- Tier 1: Microstructure metrics (requires tick-to-minute aggregation validation)
- Tier 3: Normalized spread metrics (requires correlation validation)

SLOs:
- Availability: 100% (validates Phase7 schema presence)
- Correctness: 100% (binary flags, no transformations)
- Observability: Full type hints, explicit error messages
- Maintainability: Single-responsibility extraction

Error Handling: raise_and_propagate
- ValueError if Phase7 columns missing
- ValueError if feature values invalid (not in {0, 1})
- ValueError if index mismatch during concatenation
"""

from typing import Literal

import pandas as pd


class ExnessPhase7Adapter:
    """
    Adapter to extract session features from exness-data-preprocess Phase7 schema.

    Current implementation: Tier 2 only (3 global session flags)
    Target: 121 + 3 = 124 total features

    Design rationale:
    - Session flags are pre-computed binary features (0/1)
    - No normalization or aggregation required
    - Zero correlation with price-based momentum/volatility features
    - Captures time-of-day effects (ATR-Laguerre has no time awareness)
    - Covers 24h cycle: Asian (Tokyo) → European (London) → US (NYSE)

    Example:
        >>> from exness_data_preprocess import ExnessDataProcessor
        >>> from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI
        >>>
        >>> # Get Phase7 OHLC data
        >>> processor = ExnessDataProcessor()
        >>> ohlc_df = processor.query_ohlc("EURUSD", "5m", "2024-01-01")
        >>>
        >>> # Extract RSI features (121 features after redundancy filter)
        >>> rsi_indicator = ATRAdaptiveLaguerreRSI(...)
        >>> rsi_features = rsi_indicator.fit_transform_features(ohlc_df)
        >>>
        >>> # Add session features (3 features)
        >>> combined = ExnessPhase7Adapter.combine_with_rsi_features(
        ...     rsi_features, ohlc_df
        ... )
        >>> combined.shape  # (n_bars, 88)
    """

    # Tier 2: Global Session Flags (3 features)
    # These are the ONLY features extracted in current implementation
    SESSION_FEATURES: list[str] = [
        "is_nyse_session",  # US trading hours (09:30-16:00 ET)
        "is_lse_session",  # London trading hours (08:00-16:30 GMT)
        "is_xtks_session",  # Tokyo trading hours (09:00-15:00 JST)
    ]

    # Future tiers (not yet implemented - require additional validation)
    # MICROSTRUCTURE_FEATURES = [...]  # Tier 1: Requires tick-to-minute aggregation
    # NORMALIZED_SPREAD_FEATURES = [...] # Tier 3: Requires correlation validation

    @classmethod
    def extract_session_features(cls, phase7_df: pd.DataFrame) -> pd.DataFrame:
        """
        Extract 3 session features from Phase7 OHLC DataFrame.

        Args:
            phase7_df: DataFrame with Phase7 30-column schema
                       (from exness-data-preprocess v0.7.0+)

        Returns:
            DataFrame with 3 session features:
            - is_nyse_session: INTEGER {0, 1}
            - is_lse_session: INTEGER {0, 1}
            - is_xtks_session: INTEGER {0, 1}

        Raises:
            ValueError: If required Phase7 columns missing
            ValueError: If feature values not in {0, 1}
            TypeError: If phase7_df not pd.DataFrame

        Example:
            >>> session_features = ExnessPhase7Adapter.extract_session_features(ohlc_df)
            >>> session_features.shape  # (n_bars, 3)
            >>> session_features.columns.tolist()
            ['is_nyse_session', 'is_lse_session', 'is_xtks_session']
        """
        # Validate input type
        if not isinstance(phase7_df, pd.DataFrame):
            raise TypeError(f"phase7_df must be pd.DataFrame, got {type(phase7_df)}")

        # Validate Phase7 schema (check all session features present)
        missing = [col for col in cls.SESSION_FEATURES if col not in phase7_df.columns]
        if missing:
            raise ValueError(
                f"Missing Phase7 session columns: {missing}. "
                f"Expected exness-data-preprocess Phase7 schema (v1.6.0+). "
                f"Available columns: {list(phase7_df.columns)}"
            )

        # Extract session features
        session_df = phase7_df[cls.SESSION_FEATURES].copy()

        # Validate feature values (must be binary: 0 or 1)
        for col in cls.SESSION_FEATURES:
            unique_vals = session_df[col].unique()
            if not set(unique_vals).issubset({0, 1}):
                raise ValueError(
                    f"Feature '{col}' has invalid values: {unique_vals}. "
                    f"Expected binary flags in {{0, 1}}. "
                    f"This may indicate a schema mismatch or data corruption."
                )

        return session_df

    @classmethod
    def combine_with_rsi_features(
        cls, rsi_features: pd.DataFrame, phase7_df: pd.DataFrame
    ) -> pd.DataFrame:
        """
        Combine ATR-Laguerre RSI features (121) with session features (3).

        Args:
            rsi_features: 121-column DataFrame from ATRAdaptiveLaguerreRSI.fit_transform_features()
                          (after redundancy filtering)
            phase7_df: DataFrame with Phase7 30-column schema

        Returns:
            Combined 124-column DataFrame:
            - Columns 0-120: RSI features (121 total)
            - Columns 121-123: Session features (3 total)

        Raises:
            ValueError: If indices don't match
            ValueError: If rsi_features doesn't have 121 columns
            ValueError: If Phase7 columns missing

        Example:
            >>> rsi_features = indicator.fit_transform_features(ohlc_df)
            >>> rsi_features.shape  # (n_bars, 121)
            >>>
            >>> combined = ExnessPhase7Adapter.combine_with_rsi_features(
            ...     rsi_features, ohlc_df
            ... )
            >>> combined.shape  # (n_bars, 124)
        """
        # Validate RSI features
        if not isinstance(rsi_features, pd.DataFrame):
            raise TypeError(f"rsi_features must be pd.DataFrame, got {type(rsi_features)}")

        # Validate feature count (should be 121 after redundancy filter)
        if len(rsi_features.columns) != 121:
            raise ValueError(
                f"rsi_features should have 121 columns (after redundancy filtering), "
                f"got {len(rsi_features.columns)}. "
                f"Ensure you're using ATRAdaptiveLaguerreRSI.fit_transform_features() "
                f"with apply_redundancy_filter=True (default)."
            )

        # Validate index alignment
        if not rsi_features.index.equals(phase7_df.index):
            raise ValueError(
                f"Timestamp indices don't match. "
                f"RSI features: {rsi_features.index[0]} to {rsi_features.index[-1]} "
                f"({len(rsi_features)} bars), "
                f"Phase7 df: {phase7_df.index[0]} to {phase7_df.index[-1]} "
                f"({len(phase7_df)} bars). "
                f"Both DataFrames must have identical timestamp indices."
            )

        # Extract session features
        session_features = cls.extract_session_features(phase7_df)

        # Combine (RSI features first, then session features)
        combined_df = pd.concat([rsi_features, session_features], axis=1)

        # Validate result
        assert len(combined_df.columns) == 124, (
            f"Expected 124 columns (121 RSI + 3 session), got {len(combined_df.columns)}"
        )

        return combined_df

    @classmethod
    def get_session_feature_names(cls) -> list[str]:
        """
        Get list of session feature names.

        Returns:
            List of 3 session feature names

        Example:
            >>> ExnessPhase7Adapter.get_session_feature_names()
            ['is_nyse_session', 'is_lse_session', 'is_xtks_session']
        """
        return cls.SESSION_FEATURES.copy()

    @classmethod
    def validate_phase7_schema(cls, phase7_df: pd.DataFrame) -> dict[str, bool]:
        """
        Validate that DataFrame has Phase7 schema with session features.

        Args:
            phase7_df: DataFrame to validate

        Returns:
            Dict with validation results:
            - has_nyse_session: bool
            - has_lse_session: bool
            - has_xtks_session: bool
            - all_present: bool
            - schema_version: str

        Example:
            >>> validation = ExnessPhase7Adapter.validate_phase7_schema(ohlc_df)
            >>> validation['all_present']
            True
            >>> validation['schema_version']
            'Phase7 v1.6.0+'
        """
        result = {
            "has_nyse_session": "is_nyse_session" in phase7_df.columns,
            "has_lse_session": "is_lse_session" in phase7_df.columns,
            "has_xtks_session": "is_xtks_session" in phase7_df.columns,
        }

        result["all_present"] = all(result.values())

        # Determine schema version
        if result["all_present"]:
            result["schema_version"] = "Phase7 v1.6.0+"
        elif any(result.values()):
            result["schema_version"] = "Partial Phase7 schema (missing features)"
        else:
            result["schema_version"] = "Pre-Phase7 schema (no session features)"

        return result

    @classmethod
    def get_feature_info(cls) -> dict[str, dict[str, str]]:
        """
        Get detailed information about session features.

        Returns:
            Dict mapping feature name to metadata:
            - exchange: Exchange name
            - timezone: IANA timezone
            - hours: Trading hours
            - type: Data type

        Example:
            >>> info = ExnessPhase7Adapter.get_feature_info()
            >>> info['is_nyse_session']['exchange']
            'New York Stock Exchange'
            >>> info['is_nyse_session']['hours']
            '09:30-16:00 ET'
        """
        return {
            "is_nyse_session": {
                "exchange": "New York Stock Exchange",
                "code": "XNYS",
                "timezone": "America/New_York",
                "hours": "09:30-16:00 ET",
                "type": "INTEGER {0, 1}",
                "description": "1 if during NYSE trading hours, 0 otherwise",
            },
            "is_lse_session": {
                "exchange": "London Stock Exchange",
                "code": "XLON",
                "timezone": "Europe/London",
                "hours": "08:00-16:30 GMT",
                "type": "INTEGER {0, 1}",
                "description": "1 if during LSE trading hours, 0 otherwise",
            },
            "is_xtks_session": {
                "exchange": "Tokyo Stock Exchange",
                "code": "XTKS",
                "timezone": "Asia/Tokyo",
                "hours": "09:00-15:00 JST",
                "type": "INTEGER {0, 1}",
                "description": "1 if during Tokyo Stock Exchange trading hours (excludes lunch break), 0 otherwise",
            },
        }
