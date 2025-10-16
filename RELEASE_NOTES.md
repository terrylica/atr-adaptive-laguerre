
## 3.0.0 - 2025-10-16


### ⚠️ Breaking Changes

- ⚠️ **BREAKING**: Adopt Pydantic API documentation standard for backtesting adapter Refactor backtesting.py adapter to three-layer Pydantic pattern: - Layer 1: FeatureNameType Literal with 31 feature names - Layer 2: IndicatorConfig and FeatureConfig models with Field descriptions - Layer 3: Rich docstrings with Examples sections BREAKING CHANGE: API changed from plain functions to Pydantic models - atr_laguerre_indicator(data, atr_period=14) → compute_indicator(config, data) - atr_laguerre_features(data, feature_name="rsi") → compute_feature(config, data) - make_atr_laguerre_indicator(atr_period=20) → make_indicator(atr_period=20) Benefits: - Single source of truth (code = documentation) - AI-discoverable via JSON Schema - Runtime validation at config creation time - Immutable configs (frozen=True) - Field-level descriptions for IDE autocomplete Test results: 29 passed, 96% adapter coverage, 91% models coverage Migration guide: docs/backtesting-py-integration-plan.md (v2.0.0 section)



### 📝 Other Changes

- Version 1.1.0 → 2.0.0

- Version 2.0.0 → 3.0.0



---
**Full Changelog**: https://github.com/Eon-Labs/rangebar/compare/v2.0.0...v3.0.0
