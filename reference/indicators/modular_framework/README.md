# MQL5 Modular Framework

This directory contains a modular framework for MQL5 indicators based on best practices from MQL5.com research.

## Framework Structure

```
modular_framework/
├── modules/                    # Core modules (.mqh files)
│   ├── base/                  # Base classes and interfaces
│   │   ├── IModule.mqh        # Base module interface
│   │   ├── ICalculator.mqh    # Calculator interface
│   │   └── IRenderer.mqh      # Renderer interface
│   ├── calculators/           # Calculation modules
│   │   ├── MACalculator.mqh   # Moving Average calculator
│   │   ├── RSICalculator.mqh  # RSI calculator
│   │   └── BBCalculator.mqh   # Bollinger Bands calculator
│   ├── renderers/            # Display modules
│   │   ├── LineRenderer.mqh   # Line display
│   │   ├── HistogramRenderer.mqh # Histogram display
│   │   └── LevelRenderer.mqh  # Level lines display
│   └── utilities/            # Utility modules
│       ├── TimeManager.mqh    # Time-based operations
│       ├── PriceManager.mqh   # Price data management
│       └── SignalManager.mqh  # Signal generation
├── indicators/               # Modularized indicators
│   ├── SimpleMA.mq5          # Simple modularized MA
│   ├── ModularRSI.mq5        # Modularized RSI
│   └── ComplexMulti.mq5      # Complex multi-module indicator
└── examples/                 # Usage examples
    ├── BasicExample.mq5      # Basic modular usage
    └── AdvancedExample.mq5   # Advanced multi-module usage
```

## Key Features

1. **Separation of Concerns**: Calculation, rendering, and data management are separate
2. **Reusability**: Modules can be mixed and matched across indicators
3. **Extensibility**: New modules can be added without changing existing code
4. **Maintainability**: Each module has a single responsibility
5. **Testability**: Modules can be tested independently

## Usage Pattern

1. Include required module headers
2. Create module instances in OnInit()
3. Call module methods in OnCalculate()
4. Clean up in OnDeinit()

## Best Practices Implemented

- Observer pattern for module communication
- Factory pattern for module creation
- Virtual functions for polymorphism
- Proper memory management
- Error handling and validation
- Configurable parameters per module
