# atr-adaptive-laguerre Project Memory

**Architecture**: Link Farm + Hub-and-Spoke with Progressive Disclosure
**Version**: 2.0.2 (PyPI + CodeArtifact dual-publishing functional)
**Status**: Production-ready

**Quick Navigation**: [Publishing](docs/CODEARTIFACT_SETUP.md) | [API Reference](docs/API_REFERENCE.md) | [Integration Guide](docs/backtesting-py-integration.md) | [Changelog](CHANGELOG.md)

---

## Project Essentials

### Identity
- **Package**: `atr-adaptive-laguerre`
- **Purpose**: ATR-adaptive Laguerre RSI indicator for non-anticipative feature engineering in seq-2-seq forecasting
- **Repository**: https://github.com/terrylica/atr-adaptive-laguerre
- **License**: MIT (see `docs/LICENSE` )
- **Python**: 3.10+, managed with `uv`

### Current Status (2.0.2)
- ✅ Pydantic v2 API standard implemented (Layer 1-3 pattern)
- ✅ backtesting.py integration validated
- ✅ PyPI publishing automated (GitHub Actions + OIDC)
- ✅ AWS CodeArtifact publishing automated (GitHub Actions + secrets)
- ✅ All GitHub Secrets configured (6 secrets for dual-publishing)

---

## Publishing & Distribution

### Dual Publishing Configuration
Both PyPI (public) and AWS CodeArtifact (EonLabs private) publish automatically on version tags.

**Trigger**: Push version tag matching `v*.*.*` pattern
**Timeline**: ~45 seconds total (build + publish)

**Details**: [CodeArtifact Setup Guide](docs/CODEARTIFACT_SETUP.md) - includes verification commands, troubleshooting, GitHub Secrets list

### Metadata Compatibility Issue (Resolved)
**Status**: Fixed in 2.0.2 via LICENSE file relocation

**Issue**: Hatchling generated `license-file` metadata field that CodeArtifact validator rejected
**Solution**: Move LICENSE from project root to `docs/LICENSE`, remove license declaration from `[project]` section
**Reference**: Commit `fb978cd` - "fix: remove LICENSE-File metadata field for CodeArtifact compatibility"

---

## Pydantic API Standard (v2.0.0+)

**Three-Layer Pattern**:
1. **Layer 1 - Literal Types**: `FeatureNameType` - 31 supported feature names
2. **Layer 2 - Pydantic Models**: `IndicatorConfig`, `FeatureConfig` with Field descriptions + validation
3. **Layer 3 - Rich Docstrings**: Function-level documentation with examples

**Key Files**:
- `src/atr_adaptive_laguerre/backtesting_models.py` - Literal types + Pydantic models
- `src/atr_adaptive_laguerre/backtesting_adapter.py` - Adapter implementation
- `tests/test_backtesting_adapter.py` - Test coverage (29 tests, 96%)

**Details**: [Backtesting Integration Guide](docs/backtesting-py-integration-plan.md)

---

## Dependencies & Tooling

### Build & Package Management
- **Build System**: Hatchling (via `uv build`)
- **Python Management**: `uv` 0.7.13+
- **Publication**: `twine` (automatic via GitHub Actions)

### Runtime Dependencies
```
numpy>=1.26
pandas>=2.0
numba>=0.59
pydantic>=2.0
httpx>=0.27
orjson>=3.10
platformdirs>=4.0
pyarrow>=15.0
gapless-crypto-data>=2.11.0
scipy>=1.10
```

### Development Dependencies
```
pytest>=8.0
pytest-cov>=4.1
mypy>=1.8
ruff>=0.3
hypothesis>=6.0
```

---

## Credentials & Secrets

**Method**: GitHub Secrets (for GitHub Actions)
**Source**: Doppler CLI (`aws-credentials/dev` config)

**Required GitHub Secrets** (6 total):
1. `AWS_ACCESS_KEY_ID` - from Doppler
2. `AWS_SECRET_ACCESS_KEY` - from Doppler
3. `AWS_REGION` - `us-west-2`
4. `AWS_ACCOUNT_ID` - `050214414362`
5. `CODEARTIFACT_DOMAIN` - `eonlabs`
6. `CODEARTIFACT_REPOSITORY` - `el-prediction-pipeline`

**Configuration**: See [CodeArtifact Setup](docs/CODEARTIFACT_SETUP.md) for setup & verification

---

## Workflows & Automation

### GitHub Actions Workflows
| Workflow | Trigger | Status |
|----------|---------|--------|
| `publish.yml` | Version tags (v*.*.*) | ✅ PyPI publishing via OIDC |
| `publish-codeartifact.yml` | Version tags (v*.*.*) | ✅ CodeArtifact publishing via GitHub Secrets |

**Test Coverage**: 29 tests, 96% coverage, 0 warnings

---

## Version Tracking & Semantic Versioning

**SemVer 2.0.0**: MAJOR.MINOR.PATCH

**Recent Versions**:
- 2.0.2 - CodeArtifact metadata fix + dual-publishing verified
- 2.0.1 - License configuration changes
- 2.0.0 - Pydantic v2 API refactor (BREAKING)
- 1.1.0 - Initial backtesting.py integration

**Version Locations**:
- `pyproject.toml` - Single source of truth
- `src/atr_adaptive_laguerre/__init__.py` - Exported as `__version__`

---

## Known Constraints & Workarounds

### Hatchling License Metadata
**Status**: Resolved

Hatchling automatically includes `License-File` field in wheel metadata. CodeArtifact's validator rejects unrecognized fields. Solution: Keep LICENSE outside project root or in `docs/` subdirectory.

### Column Name Handling
**Status**: Handled via adapter

backtesting.py requires Title case (Open, High, Low, Close, Volume). Package uses lowercase internally. Solution: `_convert_data_to_dataframe()` bidirectional mapping in adapter.

---

## Integration Points

### backtesting.py
- Accepts Pydantic config objects via `Strategy.I()` method
- Requires Title case OHLCV columns
- Non-anticipative guarantees enforced (no lookahead bias)

### Downstream Dependencies
- **ml-feature-set** v1.1.19+ uses atr-adaptive-laguerre as transitive dependency
- Available on both PyPI (public) and CodeArtifact (EonLabs private)

---

## Documentation Structure

```
docs/
├── README.md                              Main documentation
├── API_REFERENCE.md                       Complete API reference
├── CODEARTIFACT_SETUP.md                  Publishing setup & troubleshooting
├── backtesting-py-integration.md          Integration usage guide
├── backtesting-py-integration-plan.md     Implementation roadmap
└── LICENSE                                MIT license
```

**Deeper Reference**: See individual files for complete details, examples, and troubleshooting guides

---

## Common Tasks

### Publishing New Version
```bash
# 1. Update version in pyproject.toml (SemVer)
# 2. Commit: git commit -m "chore: bump version to X.Y.Z"
# 3. Push tag: git tag vX.Y.Z && git push origin vX.Y.Z
# 4. Monitor: GitHub Actions > Publish workflows
# 5. Verify: Both PyPI and CodeArtifact within ~1 minute
```

### Verifying Publication
**PyPI**: https://pypi.org/project/atr-adaptive-laguerre/
**CodeArtifact**: See [verification commands](docs/CODEARTIFACT_SETUP.md#verifying-in-codeartifact)

### Testing Locally
```bash
uv build                    # Build distributions
pytest                      # Run all tests
pytest --cov               # Coverage report
```

---

## Conventions

- **Language**: Neutral, promotional-free in generated docs/comments
- **File Paths**: Absolute paths with space after extension (e.g., `/path/to/file.md `)
- **Versioning**: SemVer 2.0.0 with consistent tracking across all metadata
- **Errors**: Raise and propagate, no fallbacks/defaults/retries
- **Dependencies**: Use out-of-the-box tools (uv, twine, hatchling), avoid custom implementations
