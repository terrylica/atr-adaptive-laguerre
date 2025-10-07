"""Quick test of new v0.2.0 features."""
import numpy as np
import pandas as pd
from atr_adaptive_laguerre import ATRAdaptiveLaguerreRSI, ATRAdaptiveLaguerreRSIConfig

def test_datetime_index():
    """Test datetime index support."""
    print("Test 1: DatetimeIndex support")
    dates = pd.date_range('2024-01-01', periods=100, freq='1h')
    df = pd.DataFrame({
        'open': 100 + np.cumsum(np.random.randn(100) * 0.5),
        'high': 101 + np.cumsum(np.random.randn(100) * 0.5),
        'low': 99 + np.cumsum(np.random.randn(100) * 0.5),
        'close': 100 + np.cumsum(np.random.randn(100) * 0.5),
        'volume': np.random.randint(1000, 10000, 100)
    }, index=dates)

    config = ATRAdaptiveLaguerreRSIConfig(atr_period=14, smoothing_period=5)
    indicator = ATRAdaptiveLaguerreRSI(config)

    try:
        features = indicator.fit_transform(df)
        print(f"  ✓ DatetimeIndex works! Extracted {len(features)} RSI values")
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False
    return True

def test_custom_date_column():
    """Test custom date column."""
    print("\nTest 2: Custom date column")
    df = pd.DataFrame({
        'actual_ready_time': pd.date_range('2024-01-01', periods=100, freq='1h'),
        'open': 100 + np.cumsum(np.random.randn(100) * 0.5),
        'high': 101 + np.cumsum(np.random.randn(100) * 0.5),
        'low': 99 + np.cumsum(np.random.randn(100) * 0.5),
        'close': 100 + np.cumsum(np.random.randn(100) * 0.5),
        'volume': np.random.randint(1000, 10000, 100)
    })

    config = ATRAdaptiveLaguerreRSIConfig(
        atr_period=14,
        smoothing_period=5,
        date_column='actual_ready_time'
    )
    indicator = ATRAdaptiveLaguerreRSI(config)

    try:
        features = indicator.fit_transform(df)
        print(f"  ✓ Custom date column works! Extracted {len(features)} RSI values")
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False
    return True

def test_min_lookback():
    """Test min_lookback property."""
    print("\nTest 3: min_lookback property")
    config = ATRAdaptiveLaguerreRSIConfig(atr_period=32, smoothing_period=5)
    indicator = ATRAdaptiveLaguerreRSI(config)

    print(f"  Min lookback: {indicator.min_lookback}")
    print(f"  ✓ Property accessible")
    return True

def test_incremental_update():
    """Test incremental update() method."""
    print("\nTest 4: Incremental update() method")

    # Generate historical data
    dates = pd.date_range('2024-01-01', periods=100, freq='1h')
    df = pd.DataFrame({
        'date': dates,
        'open': 100 + np.cumsum(np.random.randn(100) * 0.5),
        'high': 101 + np.cumsum(np.random.randn(100) * 0.5),
        'low': 99 + np.cumsum(np.random.randn(100) * 0.5),
        'close': 100 + np.cumsum(np.random.randn(100) * 0.5),
        'volume': np.random.randint(1000, 10000, 100)
    })

    config = ATRAdaptiveLaguerreRSIConfig(atr_period=14, smoothing_period=5)
    indicator = ATRAdaptiveLaguerreRSI(config)

    # Initialize with historical data
    rsi_batch = indicator.fit_transform(df)
    print(f"  Batch RSI (last value): {rsi_batch.iloc[-1]:.4f}")

    # Test incremental update
    new_row = {
        'open': 100,
        'high': 101,
        'low': 99,
        'close': 100.5,
        'volume': 5000
    }

    try:
        new_rsi = indicator.update(new_row)
        print(f"  ✓ Incremental update works! New RSI: {new_rsi:.4f}")
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False
    return True

def test_error_messages():
    """Test improved error messages."""
    print("\nTest 5: Improved error messages")

    # Test missing date column
    df = pd.DataFrame({
        'open': [100],
        'high': [101],
        'low': [99],
        'close': [100],
        'volume': [1000]
    })

    config = ATRAdaptiveLaguerreRSIConfig()
    indicator = ATRAdaptiveLaguerreRSI(config)

    try:
        indicator.fit_transform(df)
        print("  ✗ Should have raised error")
        return False
    except ValueError as e:
        if "Available columns" in str(e) and "Hint" in str(e):
            print(f"  ✓ Error message includes context")
            return True
        else:
            print(f"  ✗ Error message lacks context: {e}")
            return False

if __name__ == "__main__":
    print("=" * 80)
    print("Testing v0.2.0 Features")
    print("=" * 80)

    results = []
    results.append(test_datetime_index())
    results.append(test_custom_date_column())
    results.append(test_min_lookback())
    results.append(test_incremental_update())
    results.append(test_error_messages())

    print("\n" + "=" * 80)
    print(f"Results: {sum(results)}/{len(results)} passed")
    if all(results):
        print("✅ All tests passed!")
    else:
        print("❌ Some tests failed")
    print("=" * 80)
