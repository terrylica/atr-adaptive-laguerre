"""
Example 4: API Discovery via uvx/uv (No Repo Access Required).

This example demonstrates how third-party users can probe the package API
after installation from PyPI, without needing access to the source repository.

After installing from PyPI, users can run:
    uvx --from atr-adaptive-laguerre python -m examples.04_api_discovery

Or directly:
    uv run --with atr-adaptive-laguerre python examples/04_api_discovery.py

This example shows:
1. Discovering all public API exports
2. Introspecting classes and functions
3. Reading docstrings
4. Checking version and metadata
"""

import inspect
import sys

import atr_adaptive_laguerre as aal


def print_section(title: str):
    """Print formatted section header."""
    print("\n" + "=" * 80)
    print(f" {title}")
    print("=" * 80)


def discover_public_api():
    """Discover all public exports from the package."""
    print_section("1. Public API Exports")

    # Get all public symbols (exclude private/dunder)
    public_symbols = [name for name in dir(aal) if not name.startswith("_")]

    print(f"\nTotal public symbols: {len(public_symbols)}\n")

    # Categorize by type
    classes = []
    functions = []
    modules = []
    other = []

    for name in public_symbols:
        obj = getattr(aal, name)
        if inspect.isclass(obj):
            classes.append(name)
        elif inspect.isfunction(obj):
            functions.append(name)
        elif inspect.ismodule(obj):
            modules.append(name)
        else:
            other.append(name)

    # Display categorized
    print("Classes:")
    for cls in sorted(classes):
        obj = getattr(aal, cls)
        doc_first_line = (obj.__doc__ or "No documentation").split("\n")[0].strip()
        print(f"  • {cls}: {doc_first_line}")

    print(f"\nFunctions:")
    for func in sorted(functions):
        obj = getattr(aal, func)
        doc_first_line = (obj.__doc__ or "No documentation").split("\n")[0].strip()
        print(f"  • {func}: {doc_first_line}")

    if modules:
        print(f"\nModules: {', '.join(sorted(modules))}")

    if other:
        print(f"\nOther: {', '.join(sorted(other))}")


def introspect_main_class():
    """Introspect the main ATRAdaptiveLaguerreRSI class."""
    print_section("2. Main Class: ATRAdaptiveLaguerreRSI")

    cls = aal.ATRAdaptiveLaguerreRSI

    print(f"\nClass: {cls.__name__}")
    print(f"Module: {cls.__module__}")
    print(f"\nDocstring (first 500 chars):")
    print("  " + (cls.__doc__ or "No documentation")[:500].replace("\n", "\n  "))

    # Get methods
    methods = [name for name in dir(cls) if not name.startswith("_") and callable(getattr(cls, name))]

    print(f"\nPublic methods ({len(methods)}):")
    for method_name in sorted(methods):
        method = getattr(cls, method_name)
        sig = inspect.signature(method) if callable(method) else ""
        doc_first_line = (method.__doc__ or "No docs").split("\n")[0].strip()
        print(f"  • {method_name}{sig}")
        print(f"    {doc_first_line}")


def introspect_config_class():
    """Introspect the configuration class."""
    print_section("3. Configuration Class: ATRAdaptiveLaguerreRSIConfig")

    cls = aal.ATRAdaptiveLaguerreRSIConfig

    print(f"\nClass: {cls.__name__}")
    print(f"Base: {cls.__bases__}")

    # Get fields (Pydantic model)
    if hasattr(cls, "model_fields"):
        print(f"\nConfiguration Parameters:")
        for field_name, field_info in cls.model_fields.items():
            field_type = field_info.annotation
            default = field_info.default if hasattr(field_info, "default") else "N/A"
            description = field_info.description if hasattr(field_info, "description") else "No description"
            print(f"  • {field_name}: {field_type}")
            print(f"    Default: {default}")
            print(f"    {description}")


def introspect_feature_expander():
    """Introspect the FeatureExpander class."""
    print_section("4. Feature Expansion: FeatureExpander")

    cls = aal.FeatureExpander

    print(f"\nClass: {cls.__name__}")
    print(f"\nDocstring (first 300 chars):")
    print("  " + (cls.__doc__ or "No documentation")[:300].replace("\n", "\n  "))

    # Check the expand method signature
    if hasattr(cls, "expand"):
        expand_method = cls.expand
        print(f"\nKey Method: expand()")
        print(f"  Signature: {inspect.signature(expand_method)}")
        print(f"  Returns: 27 feature columns from single RSI series")


def introspect_validation_functions():
    """Introspect validation functions."""
    print_section("5. Validation Functions")

    validation_funcs = [
        "calculate_information_coefficient",
        "validate_information_coefficient",
        "validate_non_anticipative",
        "validate_ood_robustness",
    ]

    for func_name in validation_funcs:
        if hasattr(aal, func_name):
            func = getattr(aal, func_name)
            sig = inspect.signature(func)
            doc_first_line = (func.__doc__ or "No docs").split("\n")[0].strip()

            print(f"\nFunction: {func_name}")
            print(f"  Signature: {sig}")
            print(f"  {doc_first_line}")


def check_package_metadata():
    """Check package version and metadata."""
    print_section("6. Package Metadata")

    print(f"\nPackage: {aal.__name__}")
    print(f"Version: {aal.__version__}")

    # Check if __all__ is defined
    if hasattr(aal, "__all__"):
        print(f"\nExplicit exports (__all__): {len(aal.__all__)} symbols")
        print(f"  {', '.join(aal.__all__[:10])}" + (" ..." if len(aal.__all__) > 10 else ""))


def demonstrate_usage():
    """Demonstrate basic usage pattern."""
    print_section("7. Basic Usage Pattern")

    print("""
# Import main classes
from atr_adaptive_laguerre import (
    ATRAdaptiveLaguerreRSI,
    ATRAdaptiveLaguerreRSIConfig,
    FeatureExpander,
)

# Configure feature extraction
config = ATRAdaptiveLaguerreRSIConfig(
    atr_period=32,
    smoothing_period=5,
    level_up=0.85,
    level_down=0.15,
    multiplier_1=3,    # Optional: 3× base interval
    multiplier_2=12,   # Optional: 12× base interval
)

# Create feature extractor
feature = ATRAdaptiveLaguerreRSI(config)

# Extract features from OHLCV DataFrame
# Single-interval (27 features):
#   features = feature.fit_transform_features(df)
#
# Multi-interval (121 features, if multipliers set):
#   features = feature.fit_transform_features(df)

# Validate non-anticipative guarantee:
#   is_valid = feature.validate_non_anticipative(df, n_shuffles=100)
""")


def main():
    """Run all API discovery demonstrations."""
    print("=" * 80)
    print(" ATR-Adaptive Laguerre RSI: API Discovery")
    print("=" * 80)
    print(f"\nPython version: {sys.version}")
    print(f"Package location: {aal.__file__}")

    # Run all discovery functions
    discover_public_api()
    introspect_main_class()
    introspect_config_class()
    introspect_feature_expander()
    introspect_validation_functions()
    check_package_metadata()
    demonstrate_usage()

    print("\n" + "=" * 80)
    print("✓ API Discovery Complete!")
    print("\nNext Steps:")
    print("  1. Review examples/01_basic_single_interval.py for 27-feature extraction")
    print("  2. Review examples/02_multi_interval_features.py for 121-feature extraction")
    print("  3. Review examples/03_walk_forward_backtest.py for backtesting template")
    print("=" * 80)


if __name__ == "__main__":
    main()
