# AWS CodeArtifact Publishing Setup

This document explains how to configure automatic publishing to AWS CodeArtifact via GitHub Actions.

## Overview

The `atr-adaptive-laguerre` package is published to two package repositories:
- **PyPI** (public): `https://pypi.org/project/atr-adaptive-laguerre/`
- **AWS CodeArtifact** (EonLabs private): `eonlabs-050214414362.d.codeartifact.us-west-2.amazonaws.com`

Both are published automatically when you push a version tag (e.g., `git push origin v2.0.1`).

---

## GitHub Actions Workflow

**File:** `.github/workflows/publish-codeartifact.yml`

**Trigger:** On version tags matching `v*.*.*` pattern

**Jobs:**
1. `build` - Builds distributions using `uv build`
2. `publish-codeartifact` - Authenticates to AWS and uploads to CodeArtifact

---

## Required GitHub Repository Secrets

Configure these secrets in your GitHub repository settings (`Settings` > `Secrets and variables` > `Actions`):

### AWS Credentials

These credentials are used to authenticate with AWS CodeArtifact. Obtain them from your Doppler project:

```bash
doppler run --project aws-credentials --config dev -- printenv | grep AWS
```

| Secret Name | Value | Source |
|-------------|-------|--------|
| `AWS_ACCESS_KEY_ID` | Your AWS access key | `aws-credentials/dev` in Doppler |
| `AWS_SECRET_ACCESS_KEY` | Your AWS secret key | `aws-credentials/dev` in Doppler |
| `AWS_REGION` | `us-west-2` | Fixed value |
| `AWS_ACCOUNT_ID` | `050214414362` | EonLabs AWS account |

### CodeArtifact Configuration

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `CODEARTIFACT_DOMAIN` | `eonlabs` | CodeArtifact domain name |
| `CODEARTIFACT_REPOSITORY` | `el-prediction-pipeline` | Repository within the domain |

---

## Setup Instructions

### Step 1: Retrieve AWS Credentials from Doppler

```bash
doppler run --project aws-credentials --config dev -- bash << 'EOF'
echo "AWS_ACCESS_KEY_ID: $(echo $AWS_ACCESS_KEY_ID)"
echo "AWS_SECRET_ACCESS_KEY: $(echo $AWS_SECRET_ACCESS_KEY | head -c 20)..."
echo "AWS_ACCOUNT_ID: $(aws sts get-caller-identity --query Account --output text)"
EOF
```

### Step 2: Add Secrets to GitHub

1. Go to your repository: `https://github.com/terrylica/atr-adaptive-laguerre`
2. Click **Settings** > **Secrets and variables** > **Actions** > **New repository secret**
3. Add each secret from the table above:

**Example - Adding AWS_ACCESS_KEY_ID:**
- Name: `AWS_ACCESS_KEY_ID`
- Value: (paste value from Doppler)
- Click **Add secret**

### Step 3: Verify Secrets Configuration

After adding all secrets, verify they're configured:

```bash
# List secrets (values are hidden)
gh secret list --repo terrylica/atr-adaptive-laguerre
```

Expected output:
```
AWS_ACCESS_KEY_ID
AWS_ACCOUNT_ID
AWS_REGION
AWS_SECRET_ACCESS_KEY
CODEARTIFACT_DOMAIN
CODEARTIFACT_REPOSITORY
```

---

## Testing the Workflow

### Manual Test (Recommended)

1. **Make a test version bump** (don't push yet):
   ```bash
   # Update version in pyproject.toml (e.g., 2.0.0 → 2.0.1)
   # Commit changes
   git add pyproject.toml
   git commit -m "chore: bump version to 2.0.1"
   ```

2. **Create and push a test tag**:
   ```bash
   git tag v2.0.1
   git push origin v2.0.1
   ```

3. **Monitor the workflow** in GitHub Actions:
   - Go to `Actions` tab
   - Look for `Publish to AWS CodeArtifact` workflow
   - Wait for both jobs (`build` and `publish-codeartifact`) to complete

4. **Expected Success Indicators:**
   - Build job completes (creates wheel + source distribution)
   - Publish job completes with message: `200 OK` or upload progress
   - No `409 Conflict` errors (only occurs if version already exists)

### Verifying Package in CodeArtifact

After successful publication, verify the package is in CodeArtifact:

```bash
doppler run --project aws-credentials --config dev -- bash << 'EOF'
# Get temporary CodeArtifact authorization
export AWS_ACCOUNT_ID=050214414362
aws codeartifact login --tool pip \
  --repository el-prediction-pipeline \
  --domain eonlabs \
  --domain-owner $AWS_ACCOUNT_ID \
  --region us-west-2

# List available versions
pip index versions atr-adaptive-laguerre

# Expected output:
# atr-adaptive-laguerre (2.0.1)
# Available versions: 2.0.1, 2.0.0, 1.1.0, ...
EOF
```

---

## Troubleshooting

### Issue 1: Workflow fails with "Unable to locate credentials"

**Cause:** GitHub Secrets not configured or incorrect values

**Solution:**
- Verify all 6 secrets are present in GitHub repository settings
- Re-check values from Doppler (especially `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`)
- Ensure no whitespace in secret values

### Issue 2: "Package Version already exists"

**Cause:** Version already published to CodeArtifact (expected for v2.0.0)

**Solution:**
- Increment version number (e.g., v2.0.1, v2.1.0)
- Rebuild and retry
- This is expected for v2.0.0 which already exists via PyPI upstream connection

### Issue 3: "401 Unauthorized" or "403 Forbidden"

**Cause:** AWS credentials invalid or expired

**Solution:**
- Refresh credentials from Doppler: `doppler run --project aws-credentials --config dev -- aws sts get-caller-identity`
- Update GitHub Secrets with new values
- Ensure credentials have `codeartifact:*` permissions

### Issue 4: Workflow doesn't trigger

**Cause:** Tag doesn't match `v*.*.*` pattern

**Solution:**
- Use semantic versioning: `v2.0.1`, `v2.1.0`, etc. ✅
- Avoid: `v2.0`, `release-2.0.1`, `2.0.1` ❌
- Verify tag was pushed: `git push origin v2.0.1`

---

## Publishing Workflow

### Local Development

1. **Make changes** to code
2. **Update version** in `pyproject.toml` (follow SemVer)
3. **Commit changes**: `git commit -m "..."`
4. **Create tag**: `git tag v2.0.1`
5. **Push**: `git push origin main && git push origin v2.0.1`

### Automatic Actions

1. GitHub Actions detects the `v2.0.1` tag
2. Workflow `Publish to AWS CodeArtifact` starts
3. Build job: Creates wheel + source distribution
4. Publish job:
   - Configures AWS credentials from GitHub Secrets
   - Authenticates with CodeArtifact
   - Uploads distributions with twine
5. Both PyPI and CodeArtifact receive the package simultaneously

---

## Files Involved

| File | Purpose |
|------|---------|
| `.github/workflows/publish.yml` | PyPI publishing (already configured) |
| `.github/workflows/publish-codeartifact.yml` | CodeArtifact publishing (NEW) |
| `pyproject.toml` | Package metadata and version |

---

## Additional Resources

- **AWS CodeArtifact Documentation:** https://docs.aws.amazon.com/codeartifact/
- **GitHub Actions Secrets:** https://docs.github.com/en/actions/security-guides/encrypted-secrets
- **Twine Documentation:** https://twine.readthedocs.io/
- **Research Notes:** `/tmp/ATR_ADAPTIVE_LAGUERRE_CODEARTIFACT_PUBLISHING_PLAN.md`

---

## Questions?

Refer to:
1. **Local publishing troubleshooting:** `/tmp/EMPIRICAL_TESTING_RESULTS.md`
2. **CodeArtifact setup:** `/tmp/ATR_ADAPTIVE_LAGUERRE_CODEARTIFACT_PUBLISHING_PLAN.md`
3. **AWS account details:** AWS_ACCOUNT_ID = `050214414362`, Region = `us-west-2`
