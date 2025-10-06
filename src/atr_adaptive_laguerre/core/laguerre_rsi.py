"""Laguerre RSI calculator from 4-stage filter values."""


def calculate_laguerre_rsi(L0: float, L1: float, L2: float, L3: float) -> float:
    """
    Calculate Laguerre RSI from four filter stage values.

    Exact implementation from MQL5 lines 415-428:
    - Compare adjacent filter stages (L0-L1, L1-L2, L2-L3)
    - Accumulate upward movements as CU (Cumulative Up)
    - Accumulate downward movements as CD (Cumulative Down)
    - RSI = CU / (CU + CD)

    Args:
        L0: First stage value
        L1: Second stage value
        L2: Third stage value
        L3: Fourth stage value

    Returns:
        Laguerre RSI value (0.0 to 1.0)

    Note:
        Returns 0.0 if total movement is zero (neutral case).
        This is non-anticipative as it uses current bar filter values only.
    """
    CU = 0.0  # Cumulative Up movements
    CD = 0.0  # Cumulative Down movements

    # Compare L0 and L1
    if L0 >= L1:
        CU += L0 - L1
    else:
        CD += L1 - L0

    # Compare L1 and L2
    if L1 >= L2:
        CU += L1 - L2
    else:
        CD += L2 - L1

    # Compare L2 and L3
    if L2 >= L3:
        CU += L2 - L3
    else:
        CD += L3 - L2

    # Calculate RSI
    total_movement = CU + CD

    if total_movement == 0.0:
        return 0.0  # Neutral (no movement)

    return CU / total_movement


def calculate_laguerre_rsi_batch(
    filter_stages: list[tuple[float, float, float, float]]
    | tuple[tuple[float, float, float, float], ...],
) -> list[float]:
    """
    Batch calculation of Laguerre RSI from filter stages.

    Args:
        filter_stages: List of (L0, L1, L2, L3) tuples

    Returns:
        List of Laguerre RSI values (0.0 to 1.0)

    Example:
        >>> stages = [(1.0, 0.9, 0.8, 0.7), (1.1, 1.0, 0.9, 0.8)]
        >>> rsi_values = calculate_laguerre_rsi_batch(stages)
    """
    return [calculate_laguerre_rsi(*stages) for stages in filter_stages]
