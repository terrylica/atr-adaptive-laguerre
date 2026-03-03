"""JIT-compiled core loop for ATR-Adaptive Laguerre RSI.

Inlines the entire pipeline (TR → ATR → adaptive coeff → Laguerre → RSI) into a
single @njit function.  Produces bit-for-bit identical float64 results to the
pure-Python stateful classes — same operations, same order, fastmath=False.

Ring buffer replaces collections.deque; scalar floats replace dataclass state.
"""

import numpy as np
from numba import njit


@njit(cache=True)
def _core_loop_numba(
    high: np.ndarray,
    low: np.ndarray,
    close: np.ndarray,
    atr_period: int,
    base_period: float,
    adaptive_offset: float,
    out_rsi: np.ndarray,
    out_adaptive_coeff: np.ndarray,
    out_gamma: np.ndarray,
    out_L0: np.ndarray,
    out_L1: np.ndarray,
    out_L2: np.ndarray,
    out_L3: np.ndarray,
    out_min_atr: np.ndarray,
    out_max_atr: np.ndarray,
    out_atr: np.ndarray,
) -> None:
    """JIT-compiled core computation loop.

    Parameters
    ----------
    high, low, close : float64[n]
        Contiguous OHLC price arrays.
    atr_period : int
        ATR lookback window size.
    base_period : float
        Base period for adaptive calculation (== float(atr_period)).
    adaptive_offset : float
        Offset added to adaptive coefficient (default 0.75).
    out_* : float64[n]
        Pre-allocated output arrays written in-place.
    """
    n = high.shape[0]

    # --- TrueRangeState ---
    prev_close = 0.0
    first_bar = True

    # --- ATRState (ring buffer replaces deque) ---
    tr_buf = np.zeros(atr_period, dtype=np.float64)
    buf_head = 0
    buf_len = 0
    tr_sum = 0.0

    # --- LaguerreFilterState ---
    fL0 = 0.0
    fL1 = 0.0
    fL2 = 0.0
    fL3 = 0.0

    for i in range(n):
        h = high[i]
        lo = low[i]
        c = close[i]

        # Step 1: True Range (core/true_range.py TrueRangeState.update)
        if first_bar:
            tr = h - lo
            first_bar = False
        else:
            high_value = h if h > prev_close else prev_close
            low_value = lo if lo < prev_close else prev_close
            tr = high_value - low_value
        prev_close = c

        # Step 2: ATR update (core/atr.py ATRState.update) — ring buffer
        if buf_len == atr_period:
            old_tr = tr_buf[buf_head]
            tr_sum = tr_sum + tr - old_tr
        else:
            tr_sum += tr
            buf_len += 1
        tr_buf[buf_head] = tr
        buf_head = (buf_head + 1) % atr_period

        atr = tr_sum / buf_len

        # Step 2b: _update_minmax — backward accumulation scan
        if buf_len < 2:
            min_atr = atr
            max_atr = atr
        else:
            running_sum = 0.0
            min_atr = np.inf
            max_atr = -np.inf
            for k in range(1, buf_len + 1):
                idx = (buf_head - k) % atr_period
                running_sum += tr_buf[idx]
                atr_k = running_sum / k
                if atr_k < min_atr:
                    min_atr = atr_k
                if atr_k > max_atr:
                    max_atr = atr_k

        # Step 3: Adaptive coefficient (core/adaptive.py)
        _max = max_atr if max_atr > atr else atr
        _min = min_atr if min_atr < atr else atr
        if _min == _max:
            adaptive_coeff = 0.5
        else:
            adaptive_coeff = 1.0 - (atr - _min) / (_max - _min)

        # Step 4: Adaptive period
        adaptive_period = base_period * (adaptive_coeff + adaptive_offset)

        # Step 5: Gamma (core/laguerre_filter.py calculate_gamma)
        gamma = 1.0 - 10.0 / (adaptive_period + 9.0)

        # Step 6: Laguerre filter (core/laguerre_filter.py LaguerreFilterState.update)
        prev_fL0 = fL0
        prev_fL1 = fL1
        prev_fL2 = fL2

        fL0 = c + gamma * (fL0 - c)
        fL1 = prev_fL0 + gamma * (fL1 - fL0)
        fL2 = prev_fL1 + gamma * (fL2 - fL1)
        fL3 = prev_fL2 + gamma * (fL3 - fL2)

        # Step 7: Laguerre RSI (core/laguerre_rsi.py calculate_laguerre_rsi)
        CU = 0.0
        CD = 0.0
        if fL0 >= fL1:
            CU += fL0 - fL1
        else:
            CD += fL1 - fL0
        if fL1 >= fL2:
            CU += fL1 - fL2
        else:
            CD += fL2 - fL1
        if fL2 >= fL3:
            CU += fL2 - fL3
        else:
            CD += fL3 - fL2

        total_movement = CU + CD
        if total_movement == 0.0:
            rsi = 0.0
        else:
            rsi = CU / total_movement

        # Write outputs
        out_rsi[i] = rsi
        out_adaptive_coeff[i] = adaptive_coeff
        out_gamma[i] = gamma
        out_L0[i] = fL0
        out_L1[i] = fL1
        out_L2[i] = fL2
        out_L3[i] = fL3
        out_min_atr[i] = min_atr
        out_max_atr[i] = max_atr
        out_atr[i] = atr


@njit(cache=True)
def _rolling_percentile_numba(values, window):
    """Rolling percentile rank: % of values in window that current value exceeds.

    Equivalent to::

        pd.Series(values).rolling(window, min_periods=1)
            .apply(lambda x: (x[-1] > x[:-1]).sum() / len(x) * 100, raw=True)
            .fillna(50.0)

    Parameters
    ----------
    values : float64[n]
        Input array (e.g. RSI values).
    window : int
        Rolling window size.

    Returns
    -------
    float64[n]
        Percentile ranks in [0, 100].
    """
    n = len(values)
    out = np.empty(n, dtype=np.float64)
    for i in range(n):
        start = max(0, i - window + 1)
        count = i - start + 1
        current = values[i]
        gt_count = 0
        for j in range(start, i):
            if current > values[j]:
                gt_count += 1
        out[i] = gt_count / count * 100.0
    return out
