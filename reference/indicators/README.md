# MQL5 Indicators

Custom MQL5 indicators organized by functionality for MetaTrader 5 platform.

## Directory Structure

### `zigzag/` - ZigZag Indicators (5 versions)
Trend reversal detection using ZigZag pattern analysis.

- `zigzag_original.mq5` - Original ZigZag implementation
- `zigzag_v1_prod.mq5` - Production version 1
- `zigzag_v2_prod.mq5` - Production version 2
- `zigzag_v3_dev.mq5` - Development version 3
- `zigzag_v4_prod_signal.mq5` - Production version 4 with signal generation

### `bollinger_bands/` - Bollinger Bands Variants
Enhanced Bollinger Bands indicators for volatility analysis.

- `bb_delta.mq5` - Bollinger Bands delta/change indicator
- `bb_width.mq5` - Bollinger Bands width measurement

### `consecutive_patterns/` - Pattern Detection
Consecutive bar pattern recognition for trend continuation/reversal.

- `consecutive_contraction_bar.mq5` - Detects consecutive contracting bars
- `consecutive_expension_dot.mq5` - Detects consecutive expansion patterns
- `consecutive_pattern_combined.mq5` - Combined pattern detection system

### `atr_adaptive/` - ATR-Based Adaptive Indicators
Adaptive Laguerre RSI using ATR for dynamic smoothing.

- `atr_adaptive_laguerre_rsi_original.mq5` - Original implementation
- `atr_adaptive_laguerre_rsi_refactor_for_python.mq5` - Refactored for Python integration
- `atr_adaptive_laguerre_rsi_custom_interval.mq5` - Custom interval variant

### `custom_intervals/` - Custom Timeframe Indicators
Indicators supporting custom time intervals beyond standard MT5 periods.

- `custom_interval_demo.mq5` - Basic custom interval demonstration
- `custom_interval_advanced_demo.mq5` - Advanced custom interval features

### `basic/` - Basic Technical Indicators
Fundamental indicators for general analysis.

- `moving_average.mq5` - Moving average indicator
- `tick_volume.mq5` - Tick volume indicator

### `modular_framework/` - Indicator Development Framework
Object-oriented framework for building modular, maintainable indicators.

**Structure:**
```
modular_framework/
├── examples/
│   └── BasicExample.mq5          # Example indicator using framework
├── indicators/
│   └── SimpleMA.mq5              # Simple MA using framework
├── modules/
│   ├── base/                     # Interface definitions
│   │   ├── ICalculator.mqh
│   │   ├── IModule.mqh
│   │   └── IRenderer.mqh
│   ├── calculators/              # Calculation modules
│   │   └── MACalculator.mqh
│   └── renderers/                # Rendering modules
│       └── LineRenderer.mqh
├── README.md                     # Framework documentation
└── test_compilation.mq5          # Test compilation script
```

**Purpose:** Separates calculation logic from rendering for better code reuse and maintainability.

## Installation

1. Copy desired indicator(s) to MetaTrader 5 `Indicators/` directory
2. Compile in MetaEditor
3. Restart MetaTrader 5 or refresh indicators

## Development Notes

- **Version Control**: Multiple versions maintained (original, prod, dev)
- **Python Integration**: Some indicators refactored for Python data pipeline integration
- **Custom Intervals**: Support for non-standard timeframes for advanced backtesting
- **Modular Design**: Framework enables rapid indicator development with consistent architecture

## Related

- See `../tradingview/` for TradingView Pine Script indicators
- See `modular_framework/README.md` for framework usage details
