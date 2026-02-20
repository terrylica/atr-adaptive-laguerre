#!/usr/bin/env bash
# PyPI Publishing via mise — local-only, no GitHub Actions.
#
# Retrieves the PyPI token from 1Password (Claude Automation vault) and
# publishes the built wheel + sdist in dist/ to PyPI via uv publish.
#
# Called by: mise run release:pypi
# Prerequisites:
#   - uv installed
#   - op (1Password CLI) installed
#   - dist/ populated by mise run release:sync (uv build)
#   - OP_SERVICE_ACCOUNT_TOKEN in env, or biometric auth available

set -euo pipefail

# ---- 1Password configuration ------------------------------------------------
# "PyPI Token - terrylica-pypi-entire-account-token" in Claude Automation vault
OP_PYPI_ITEM="${OP_PYPI_ITEM:-zdc7ap2ixpqgtpq62xm2davi7e}"
OP_PYPI_VAULT="${OP_PYPI_VAULT:-Claude Automation}"
PYPI_VERIFY_DELAY="${PYPI_VERIFY_DELAY:-5}"

# ---- Tool discovery ---------------------------------------------------------
discover_uv() {
    if command -v uv &>/dev/null; then echo "uv"; return 0; fi
    for p in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" \
              "/opt/homebrew/bin/uv" "/usr/local/bin/uv"; do
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done
    return 1
}

discover_op() {
    if command -v op &>/dev/null; then echo "op"; return 0; fi
    for p in "/opt/homebrew/bin/op" "/usr/local/bin/op" "$HOME/.local/bin/op"; do
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done
    return 1
}

UV_CMD=""
if ! UV_CMD=$(discover_uv); then
    echo "✗ uv not found. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

OP_CMD=""
if ! OP_CMD=$(discover_op); then
    echo "✗ op (1Password CLI) not found. Install: brew install 1password-cli"
    exit 1
fi

# ---- Version ----------------------------------------------------------------
VERSION=$(grep '^version' pyproject.toml | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "Publishing atr-adaptive-laguerre==$VERSION to PyPI..."
echo ""

# ---- Verify dist/ exists ----------------------------------------------------
WHEEL=$(find dist -name "*${VERSION}*.whl" 2>/dev/null | head -1 || true)
if [[ -z "$WHEEL" ]]; then
    echo "✗ No wheel found for v$VERSION in dist/. Run: mise run release:sync first"
    exit 1
fi
echo "→ Wheel:  $(basename "$WHEEL")"
SDIST=$(find dist -name "*${VERSION}*.tar.gz" 2>/dev/null | head -1 || true)
[[ -n "$SDIST" ]] && echo "→ Sdist:  $(basename "$SDIST")"
echo ""

# ---- Fetch PyPI token from 1Password ----------------------------------------
echo "→ Fetching PyPI token from 1Password (vault: $OP_PYPI_VAULT)..."

# Use service account token if available (headless), otherwise biometric
if [[ -f "$HOME/.claude/.secrets/op-service-account-token" ]]; then
    PYPI_TOKEN=$(OP_SERVICE_ACCOUNT_TOKEN="$(cat "$HOME/.claude/.secrets/op-service-account-token")" \
        $OP_CMD item get "$OP_PYPI_ITEM" \
            --vault "$OP_PYPI_VAULT" \
            --fields "credential" \
            --reveal 2>/dev/null)
else
    PYPI_TOKEN=$($OP_CMD item get "$OP_PYPI_ITEM" \
        --vault "$OP_PYPI_VAULT" \
        --fields "credential" \
        --reveal 2>/dev/null)
fi

if [[ -z "$PYPI_TOKEN" ]]; then
    echo "✗ Failed to retrieve PyPI token from 1Password"
    exit 1
fi
echo "  ✓ Token retrieved (${#PYPI_TOKEN} chars)"
echo ""

# ---- Publish ----------------------------------------------------------------
echo "→ Publishing to PyPI..."
# Build file list via find (SC2012: avoid ls for glob matching)
mapfile -t DIST_FILES < <(find dist -name "*${VERSION}*.whl" -o -name "*${VERSION}*.tar.gz" 2>/dev/null)
UV_PUBLISH_TOKEN="$PYPI_TOKEN" $UV_CMD publish "${DIST_FILES[@]}"

echo ""
echo "✓ Published atr-adaptive-laguerre==$VERSION"
echo ""

# ---- Verify -----------------------------------------------------------------
echo "→ Verifying PyPI availability (waiting ${PYPI_VERIFY_DELAY}s)..."
sleep "$PYPI_VERIFY_DELAY"

PYPI_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://pypi.org/pypi/atr-adaptive-laguerre/${VERSION}/json" 2>/dev/null || echo "000")

if [[ "$PYPI_STATUS" == "200" ]]; then
    echo "  ✓ https://pypi.org/project/atr-adaptive-laguerre/$VERSION/ — LIVE"
else
    echo "  ⚠ PyPI not yet showing v$VERSION (HTTP $PYPI_STATUS) — CDN propagation may take a few minutes"
fi
echo ""
