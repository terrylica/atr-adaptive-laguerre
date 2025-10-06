"""Laguerre 4-stage cascade filter with O(1) incremental updates (talipp pattern)."""

from dataclasses import dataclass


@dataclass
class LaguerreFilterState:
    """
    Stateful 4-stage Laguerre cascade filter.

    Follows talipp O(1) incremental pattern for online computation.
    Non-anticipative: each stage depends only on previous stage values.

    The Laguerre filter is a low-lag smoothing filter that uses a cascade
    of four stages with exponential smoothing at each stage.

    Formula (MQL5 lines 406-412):
        L0[i] = price + gamma * (L0[i-1] - price)
        L1[i] = L0[i-1] + gamma * (L1[i-1] - L0[i])
        L2[i] = L1[i-1] + gamma * (L2[i-1] - L1[i])
        L3[i] = L2[i-1] + gamma * (L3[i-1] - L2[i])

    Attributes:
        L0: First stage (price input)
        L1: Second stage
        L2: Third stage
        L3: Fourth stage (output)
        gamma: Filter coefficient (0 to 1)
    """

    L0: float = 0.0
    L1: float = 0.0
    L2: float = 0.0
    L3: float = 0.0
    gamma: float = 0.0

    def update(self, price: float, gamma: float) -> tuple[float, float, float, float]:
        """
        O(1) incremental update for single price bar.

        Args:
            price: Current price value
            gamma: Filter coefficient (0 to 1, closer to 1 = smoother)

        Returns:
            Tuple of (L0, L1, L2, L3) values

        Note:
            Non-anticipative: uses previous stage values (L0[i-1], L1[i-1], etc.)
            This exactly matches MQL5 logic (lines 406-412).
        """
        # Store previous values for cascade
        prev_L0 = self.L0
        prev_L1 = self.L1
        prev_L2 = self.L2

        # Update cascade (exact MQL5 formulas)
        # L0: First stage with price input
        self.L0 = price + gamma * (self.L0 - price)

        # L1: Second stage using previous L0
        self.L1 = prev_L0 + gamma * (self.L1 - self.L0)

        # L2: Third stage using previous L1
        self.L2 = prev_L1 + gamma * (self.L2 - self.L1)

        # L3: Fourth stage using previous L2
        self.L3 = prev_L2 + gamma * (self.L3 - self.L2)

        return (self.L0, self.L1, self.L2, self.L3)

    def initialize(self, price: float) -> None:
        """
        Initialize all stages with same price value.

        Used for first bar (MQL5 lines 432-434).

        Args:
            price: Initial price value
        """
        self.L0 = self.L1 = self.L2 = self.L3 = price

    def reset(self) -> None:
        """Reset state for new data stream."""
        self.L0 = self.L1 = self.L2 = self.L3 = 0.0
        self.gamma = 0.0


def calculate_gamma(period: float) -> float:
    """
    Calculate gamma coefficient from period.

    Formula (MQL5 line 403):
        gamma = 1.0 - 10.0 / (period + 9.0)

    Args:
        period: Filter period (higher = smoother)

    Returns:
        Gamma coefficient (0 to 1)

    Note:
        Higher period → gamma closer to 1.0 → slower/smoother filter
        Lower period → gamma closer to 0.0 → faster/responsive filter
    """
    return 1.0 - 10.0 / (period + 9.0)


def calculate_laguerre_batch(
    prices: list[float] | tuple[float, ...], period: float
) -> list[tuple[float, float, float, float]]:
    """
    Batch calculation of Laguerre filter stages.

    Args:
        prices: Price values
        period: Filter period

    Returns:
        List of (L0, L1, L2, L3) tuples for each bar

    Note:
        Uses stateful calculator for non-anticipative property.
    """
    state = LaguerreFilterState()
    gamma = calculate_gamma(period)
    results = []

    for i, price in enumerate(prices):
        if i == 0:
            # Initialize first bar
            state.initialize(price)
            results.append((state.L0, state.L1, state.L2, state.L3))
        else:
            # Update subsequent bars
            result = state.update(price, gamma)
            results.append(result)

    return results
