"""Adaptive coefficient calculation for volatility normalization."""


def calculate_adaptive_coefficient(
    current_atr: float, min_atr: float, max_atr: float
) -> float:
    """
    Calculate adaptive coefficient from ATR volatility measures.

    Exact implementation from MQL5 lines 290-292:
    - First determine actual min/max by comparing with current ATR
    - Normalize current ATR position within range
    - Invert normalization (1.0 - normalized)

    Formula:
        _max = max(max_atr, current_atr)
        _min = min(min_atr, current_atr)
        coeff = 1.0 - (current_atr - _min) / (_max - _min)

    Args:
        current_atr: Current ATR value
        min_atr: Minimum ATR in lookback period
        max_atr: Maximum ATR in lookback period

    Returns:
        Adaptive coefficient (0.0 to 1.0)
        - Near 1.0: Low volatility → slower/smoother filter
        - Near 0.0: High volatility → faster/responsive filter

    Note:
        Returns 0.5 if min == max (no volatility range).
        This exactly matches MQL5 logic.
    """
    # Determine actual min/max (handles edge cases)
    _max = max(max_atr, current_atr)
    _min = min(min_atr, current_atr)

    # Avoid division by zero
    if _min == _max:
        return 0.5  # Neutral coefficient

    # Normalized position: (current - min) / (max - min) ∈ [0, 1]
    # Inverted: 1.0 - normalized → high volatility gives low coefficient
    return 1.0 - (current_atr - _min) / (_max - _min)


def calculate_adaptive_period(
    base_period: float, coefficient: float, offset: float = 0.75
) -> float:
    """
    Calculate adaptive period for Laguerre filter.

    Exact implementation from MQL5 line 295:
        period = base_period * (coefficient + 0.75)

    Args:
        base_period: Base ATR period
        coefficient: Adaptive coefficient (0.0 to 1.0)
        offset: Offset value (default 0.75)

    Returns:
        Adaptive period for Laguerre filter

    Note:
        The 0.75 offset ensures period ranges from:
        - Min: base_period * 0.75 (high volatility)
        - Max: base_period * 1.75 (low volatility)
    """
    return base_period * (coefficient + offset)


def calculate_adaptive_coefficient_batch(
    atr_values: list[float] | tuple[float, ...],
    min_atr_values: list[float] | tuple[float, ...],
    max_atr_values: list[float] | tuple[float, ...],
) -> list[float]:
    """
    Batch calculation of adaptive coefficients.

    Args:
        atr_values: Current ATR values
        min_atr_values: Minimum ATR values
        max_atr_values: Maximum ATR values

    Returns:
        List of adaptive coefficients (0.0 to 1.0)

    Raises:
        ValueError: If input arrays have different lengths
    """
    if len(atr_values) != len(min_atr_values) or len(atr_values) != len(max_atr_values):
        raise ValueError("Input arrays must have equal length")

    return [
        calculate_adaptive_coefficient(atr, min_atr, max_atr)
        for atr, min_atr, max_atr in zip(atr_values, min_atr_values, max_atr_values)
    ]
