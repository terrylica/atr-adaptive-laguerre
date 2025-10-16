# backtesting.py Integration Implementation Plan

**Version**: 1.0.0
**Created**: 2025-10-10
**Target Release**: v1.1.0

## Objectives

Enable atr-adaptive-laguerre package as indicator for backtesting.py framework while maintaining existing ML feature engineering capabilities.

## Service Level Objectives (SLOs)

### Availability
- Adapter functions callable without dependencies missing (100% when backtesting.py installed)
- Graceful import failure with clear error message when backtesting.py not installed

### Correctness
- Column mapping bidirectional accuracy: 100%
- Non-anticipative property maintained: 100% (validated via progressive subset testing)
- Output value range [0.0, 1.0]: 100%
- Output length matches input length: 100%

### Observability
- Clear error messages for missing columns (specify which columns missing)
- Clear error messages for invalid data types
- Clear error messages for invalid feature names

### Maintainability
- Zero core computation changes (adapter only)
- API surface: 3 public functions
- Test coverage: >90% for adapter module
- Documentation: usage examples for all 3 functions

## Architecture

### File Structure
```
src/atr_adaptive_laguerre/
├── backtesting_adapter.py         # NEW
├── __init__.py                    # UPDATE: add exports

tests/
├── test_backtesting_adapter.py    # NEW

docs/
├── backtesting-py-integration.md  # NEW
└── backtesting-py-integration-plan.md  # THIS FILE
```

## Implementation Phases

### Phase 1: Core Adapter Module
**File**: `src/atr_adaptive_laguerre/backtesting_adapter.py`

**Functions**:
1. `atr_laguerre_indicator(data, atr_period=14, smoothing_period=5, **kwargs) -> np.ndarray`
   - Main RSI indicator for backtesting.py
   - Handles data.df accessor or direct DataFrame
   - Column mapping: Title case → lowercase
   - Returns numpy array

2. `atr_laguerre_features(data, feature_name='rsi', **kwargs) -> np.ndarray`
   - Extract single feature from 31-feature expansion
   - Same data handling as above
   - Returns single feature as numpy array

3. `make_atr_laguerre_indicator(atr_period=14, **kwargs) -> Callable`
   - Factory function for parameterized indicators
   - Returns closure with captured parameters
   - Sets `__name__` for plot legends

**Column Mapping**:
```python
COLUMN_MAPPING = {
    'Open': 'open',
    'High': 'high',
    'Low': 'low',
    'Close': 'close',
    'Volume': 'volume'
}
```

**Error Handling** (strict propagation):
- `TypeError`: Invalid data object type → propagate
- `ValueError`: Missing required columns → propagate with column list
- `ValueError`: Invalid feature name → propagate with available features
- No try/except blocks with fallbacks
- No default value substitution
- No silent failures

### Phase 2: Package Integration
**File**: `src/atr_adaptive_laguerre/__init__.py`

**Changes**:
```python
# Add imports
from atr_adaptive_laguerre.backtesting_adapter import (
    atr_laguerre_indicator,
    atr_laguerre_features,
    make_atr_laguerre_indicator,
)

# Update __all__
__all__ = [
    # ... existing ...
    "atr_laguerre_indicator",
    "atr_laguerre_features",
    "make_atr_laguerre_indicator",
]
```

### Phase 3: Testing
**File**: `tests/test_backtesting_adapter.py`

**Test Cases**:
1. Basic indicator computation
2. Column name mapping (Title case → lowercase)
3. Data object with .df accessor
4. Direct DataFrame input
5. Custom parameters
6. Feature extraction (all 31 features)
7. Factory function
8. Error propagation (missing columns, invalid types, invalid features)
9. Non-anticipative property validation
10. Output range validation [0.0, 1.0]
11. Output length validation

**No mocking** - use real computation with synthetic data

### Phase 4: Documentation
**File**: `docs/backtesting-py-integration.md`

**Sections**:
1. Installation
2. Basic usage example
3. Multi-feature usage example
4. Parameter optimization example
5. Available features table
6. API reference
7. SLO guarantees
8. Comparison: backtesting vs ML use cases

### Phase 5: Version Update
**Files**: `pyproject.toml`, `src/atr_adaptive_laguerre/__init__.py`

**Changes**:
- Version: `1.0.12` → `1.1.0` (MINOR bump per SemVer)
- Rationale: New feature, no breaking changes

## Dependencies

**Required** (already present):
- pandas
- numpy

**Optional** (not added to requirements):
- backtesting (user installs if needed)

**Approach**: No hard dependency, graceful degradation

## Testing Strategy

### Unit Tests
- All adapter functions with synthetic data
- Error conditions (invalid inputs)
- Edge cases (empty DataFrames, single row)

### Integration Tests
- Real backtesting.py Strategy.I() integration (if installed)
- Skip if backtesting.py not available

### Validation Tests
- Non-anticipative property (progressive subset comparison)
- Output correctness (compare with direct fit_transform)
- Value range validation

## Success Criteria

- [x] All tests pass (28/28 adapter tests, 100% coverage)
- [x] Test coverage >90% for adapter module (100% achieved)
- [x] Documentation complete with examples
- [x] No changes to core computation modules
- [x] Backward compatibility maintained (adapter-only changes)
- [x] SLOs documented and validated

## Implementation Status

**Version**: 1.1.0
**Status**: ✅ COMPLETED
**Date**: 2025-10-10

### Deliverables

1. ✅ `src/atr_adaptive_laguerre/backtesting_adapter.py` (39 statements, 100% coverage)
   - `atr_laguerre_indicator()` - Main RSI indicator
   - `atr_laguerre_features()` - Feature extraction
   - `make_atr_laguerre_indicator()` - Factory function

2. ✅ `src/atr_adaptive_laguerre/__init__.py` - Updated exports

3. ✅ `tests/test_backtesting_adapter.py` - Comprehensive test suite
   - 28 tests covering all functions
   - 100% coverage of adapter module
   - SLO validation (correctness, non-anticipative, error handling)

4. ✅ `docs/backtesting-py-integration.md` - Complete documentation
   - API reference for all 3 functions
   - Usage examples (basic, multi-feature, dual-timeframe, optimization)
   - Available features table (31 features)
   - Data requirements and error handling

5. ✅ Version updated to 1.1.0 (MINOR bump per SemVer)

### Test Results

```
28 passed, 0 warnings in 1.37s
Coverage: 100% for backtesting_adapter.py
```

**Warnings Resolved**:
- ✅ Pydantic V2 deprecation warnings (3): Migrated `class Config:` → `ConfigDict`
  - Fixed in: `src/atr_adaptive_laguerre/features/base.py`
  - Fixed in: `src/atr_adaptive_laguerre/data/schema.py`
- ✅ Single-interval mode warnings (35): Suppressed in adapter (intentional usage)
  - Suppressed in: `src/atr_adaptive_laguerre/backtesting_adapter.py:140, 222`

### Validation

- ✅ All adapter tests pass
- ✅ Imports successful
- ✅ Column mapping bidirectional (Title ↔ lowercase)
- ✅ Non-anticipative property maintained
- ✅ Output range [0.0, 1.0] validated
- ✅ Error propagation strict (no fallbacks)
- ✅ Clear error messages for all failure modes

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Column name case sensitivity | Explicit mapping with validation |
| backtesting.py API changes | Pin minimum version in docs |
| Performance regression | No changes to core, adapter is thin wrapper |
| Breaking changes | Purely additive, SemVer compliance |

## Timeline

Estimated: 2-3 hours
- Phase 1: 45 min
- Phase 2: 10 min
- Phase 3: 60 min
- Phase 4: 30 min
- Phase 5: 15 min

---

## v2.0.0: Pydantic API Documentation Standard Refactor

**Version**: 2.0.0
**Created**: 2025-10-13
**Status**: ✅ COMPLETED
**Breaking Change**: YES - API changed from plain functions to Pydantic models

### Motivation

Adopt Pydantic API Documentation Standard (industry standard: 8000+ PyPI packages, 360M+ downloads/month) for:
- Single source of truth (code = documentation)
- AI-discoverable via JSON Schema
- Runtime validation at parameter construction time
- Field-level descriptions for machine-readable docs
- Eliminates README/AGENTS.md fragmentation

### Architecture Changes

**Three-Layer Pattern**:

**Layer 1**: Literal types define valid parameter values
```python
# backtesting_models.py
FeatureNameType = Literal[
    "rsi", "regime", "regime_bearish", "regime_neutral",
    # ... all 31 features
]
```

**Layer 2**: Pydantic models with Field descriptions
```python
class IndicatorConfig(BaseModel):
    atr_period: int = Field(
        default=14, ge=10, le=30,
        description="ATR lookback period for volatility adaptation..."
    )
    # ... all parameters with validation and descriptions

    model_config = ConfigDict(frozen=True, json_schema_extra={...})

class FeatureConfig(BaseModel):
    feature_name: FeatureNameType = Field(...)
    # ... inherits indicator parameters
```

**Layer 3**: Rich docstrings in adapter functions
```python
def compute_indicator(config: IndicatorConfig, data: Any) -> np.ndarray:
    """
    Compute ATR-Adaptive Laguerre RSI indicator for backtesting.py Strategy.I().

    Examples:
        >>> from atr_adaptive_laguerre import IndicatorConfig, compute_indicator
        >>> config = IndicatorConfig()
        >>> class MyStrategy(Strategy):
        ...     def init(self):
        ...         self.rsi = self.I(compute_indicator, config, self.data)
    """
```

### Breaking Changes

**v1.1.0 API (DEPRECATED)**:
```python
# Plain function parameters
result = atr_laguerre_indicator(data, atr_period=14, smoothing_period=5)
result = atr_laguerre_features(data, feature_name="rsi")
indicator = make_atr_laguerre_indicator(atr_period=20)
```

**v2.0.0 API (NEW)**:
```python
# Pydantic model parameters
config = IndicatorConfig(atr_period=14, smoothing_period=5)
result = compute_indicator(config, data)

config = FeatureConfig(feature_name="rsi")
result = compute_feature(config, data)

indicator = make_indicator(atr_period=20)  # Validates at creation
```

### Implementation

**New Files**:
1. `src/atr_adaptive_laguerre/backtesting_models.py` (22 statements, 91% coverage)
   - `FeatureNameType` Literal with 31 feature names
   - `IndicatorConfig` Pydantic model
   - `FeatureConfig` Pydantic model with `supported_features()` helper

**Updated Files**:
1. `src/atr_adaptive_laguerre/backtesting_adapter.py` (46 statements, 96% coverage)
   - `atr_laguerre_indicator()` → `compute_indicator(config, data)`
   - `atr_laguerre_features()` → `compute_feature(config, data)`
   - `make_atr_laguerre_indicator()` → `make_indicator()` with validation

2. `src/atr_adaptive_laguerre/__init__.py`
   - Version: 1.1.0 → 2.0.0
   - Exports: `IndicatorConfig`, `compute_indicator`, `compute_feature`, `make_indicator`
   - Note: backtesting `FeatureConfig` not exported at top level (naming collision with core `FeatureConfig`)

3. `tests/test_backtesting_adapter.py`
   - Updated all 29 tests (was 28 tests, added 1 validation test)
   - Updated imports and all function calls
   - New test: `test_factory_validates_parameters()` - validates Pydantic enforcement

### Test Results

```
29 passed in 2.48s
Coverage: 96% backtesting_adapter.py, 91% backtesting_models.py
0 warnings
```

**All SLO guarantees maintained**:
- ✅ Correctness: Column mapping bidirectional accuracy 100%
- ✅ Correctness: Non-anticipative property maintained 100%
- ✅ Correctness: Output value range [0.0, 1.0]: 100%
- ✅ Correctness: Output length matches input length: 100%
- ✅ Observability: Clear error messages + Pydantic ValidationError
- ✅ Maintainability: Single source of truth, AI-discoverable schema

### Migration Guide

**For users on v1.x**:

```python
# Before (v1.x)
from atr_adaptive_laguerre import atr_laguerre_indicator
class MyStrategy(Strategy):
    def init(self):
        self.rsi = self.I(atr_laguerre_indicator, self.data, atr_period=20)

# After (v2.x)
from atr_adaptive_laguerre import IndicatorConfig, compute_indicator
class MyStrategy(Strategy):
    def init(self):
        config = IndicatorConfig(atr_period=20)
        self.rsi = self.I(compute_indicator, config, self.data)
```

**Benefits of upgrade**:
- Parameter validation at config creation time (fail fast)
- IDE autocomplete for all parameters
- Field-level descriptions via `help(IndicatorConfig)`
- JSON Schema generation via `IndicatorConfig.model_json_schema()`
- Immutable configs (frozen=True prevents accidental mutation)

### References

- Pydantic v2 docs: https://docs.pydantic.dev/latest/
- User specification: `~/.claude/specifications/pydantic-api-documentation-standard.yaml`
- Industry adoption: OpenAI SDK, Anthropic SDK, Google ADK, FastAPI, LangChain

---

## References

- backtesting.py docs: https://kernc.github.io/backtesting.py/
- API probe results: `/tmp/probe/` (ephemeral, captured in plan)
- Research report: Task agent output (2025-10-10)
- Pydantic standard: `~/.claude/specifications/pydantic-api-documentation-standard.yaml`
