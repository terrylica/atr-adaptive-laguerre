# atr-adaptive-laguerre

Guidance for Claude Code when working in this repository.

## Status

| Item | Value |
|------|-------|
| **Version** | 2.0.3 |
| **License** | MIT |
| **Python** | 3.10+ (managed with `uv`) |
| **Status** | Production-ready |

---

## Quick Links

| Topic | Document |
|-------|----------|
| **Installation & Features** | [docs/README.md](docs/README.md) |
| **API Reference** | [docs/API_REFERENCE.md](docs/API_REFERENCE.md) |
| **backtesting.py Integration** | [docs/backtesting-py-integration.md](docs/backtesting-py-integration.md) |
| **PyPI + CodeArtifact Publishing** | [docs/CODEARTIFACT_SETUP.md](docs/CODEARTIFACT_SETUP.md) |
| **Release History** | [CHANGELOG.md](CHANGELOG.md) |
| **Design & Architecture** | [docs/backtesting-py-integration-plan.md](docs/backtesting-py-integration-plan.md) |
| **Feature Engineering Design** | [FEATURE_EXTRACTION_PLAN.md](FEATURE_EXTRACTION_PLAN.md) |
| **Validation Framework** | [TEMPORAL_LEAKAGE_TEST_PLAN.md](TEMPORAL_LEAKAGE_TEST_PLAN.md) |

---

## Development Commands

```bash
# Build
uv build                    # Wheel + sdist distributions

# Test
pytest                      # All tests (29 tests, 96% coverage)
pytest --cov               # Coverage report
pytest -k test_name        # Single test by name

# Quality
ruff check .               # Lint
mypy src/                  # Type check

# Publish (automatic via GitHub Actions on version tag)
git tag v2.0.3 && git push origin v2.0.3
```

---

## Publishing

Both PyPI and AWS CodeArtifact publish automatically when pushing version tags (e.g., `v2.0.3`).

**Setup required**: 6 GitHub Secrets configured for CodeArtifact.
See [docs/CODEARTIFACT_SETUP.md](docs/CODEARTIFACT_SETUP.md) for details and verification.

---

## Known Issues

**Hatchling License Metadata** (v2.0.2 fix): LICENSE file is in `docs/` directory to prevent CodeArtifact validator rejection of auto-generated `license-file` metadata field.

---

## Architecture

Three-layer Pydantic v2 API pattern:
- **Layer 1**: Type definitions (`FeatureNameType` Literal with 31 features)
- **Layer 2**: Configuration models (`IndicatorConfig`, `FeatureConfig`)
- **Layer 3**: Implementation functions (`compute_indicator`, `compute_feature`, `make_indicator`)

Details: [docs/backtesting-py-integration-plan.md](docs/backtesting-py-integration-plan.md)

---

## Repository

- **GitHub**: https://github.com/terrylica/atr-adaptive-laguerre
- **PyPI**: https://pypi.org/project/atr-adaptive-laguerre/
- **CodeArtifact**: eonlabs domain, el-prediction-pipeline repository
