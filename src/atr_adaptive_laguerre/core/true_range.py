"""True Range calculator with O(1) incremental updates (talipp pattern)."""

from dataclasses import dataclass


@dataclass
class TrueRangeState:
    """
    Stateful True Range calculator.

    Follows talipp O(1) incremental pattern for online computation.
    Non-anticipative: only uses previous close for current TR calculation.

    Formula:
        First bar: TR = high - low
        Subsequent: TR = max(high, prev_close) - min(low, prev_close)
    """

    prev_close: float | None = None
    current_tr: float = 0.0

    def update(self, high: float, low: float, close: float) -> float:
        """
        O(1) incremental update for single bar.

        Args:
            high: Current bar's high price
            low: Current bar's low price
            close: Current bar's close price

        Returns:
            True Range value for current bar

        Note:
            Non-anticipative: uses prev_close from previous bar only.
            This guarantees no lookahead bias.
        """
        if self.prev_close is None:
            # First bar case: simple range
            self.current_tr = high - low
        else:
            # True Range: max of (high, prev_close) - min of (low, prev_close)
            # This captures gaps: if price gaps up, prev_close < low
            # if price gaps down, prev_close > high
            high_value = max(high, self.prev_close)
            low_value = min(low, self.prev_close)
            self.current_tr = high_value - low_value

        # Store close for next bar (non-anticipative)
        self.prev_close = close

        return self.current_tr

    def reset(self) -> None:
        """Reset state for new data stream."""
        self.prev_close = None
        self.current_tr = 0.0


def calculate_true_range_batch(
    high: list[float] | tuple[float, ...],
    low: list[float] | tuple[float, ...],
    close: list[float] | tuple[float, ...],
) -> list[float]:
    """
    Batch calculation of True Range for historical data.

    Args:
        high: High prices
        low: Low prices
        close: Close prices

    Returns:
        List of True Range values

    Note:
        Uses stateful calculator internally to maintain non-anticipative property.
    """
    if len(high) != len(low) or len(high) != len(close):
        raise ValueError("Input arrays must have equal length")

    state = TrueRangeState()
    tr_values = []

    for h, l, c in zip(high, low, close):
        tr = state.update(h, l, c)
        tr_values.append(tr)

    return tr_values
