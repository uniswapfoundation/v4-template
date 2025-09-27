# Branch Protection Setup Guide

This document explains how to set up branch protection rules for the uniPerp repository to enforce the CI/CD pipeline.

## Required Branch Protection Rules

### Main Branch Protection

Navigate to your repository settings and configure the following for the `main` branch:

1. **Protect matching branches**: ✅ Enabled
2. **Restrict pushes that create files**: ✅ Enabled 
3. **Require a pull request before merging**: ✅ Enabled
   - **Require approvals**: 1 (adjust as needed for your team)
   - **Dismiss stale PR approvals when new commits are pushed**: ✅ Enabled
   - **Require review from code owners**: ✅ Enabled (if you have a CODEOWNERS file)

4. **Require status checks to pass before merging**: ✅ Enabled
   - **Require branches to be up to date before merging**: ✅ Enabled
   - **Required status checks**:
     - `Run Tests` (runs all 176 test functions)

5. **Require conversation resolution before merging**: ✅ Enabled
6. **Require signed commits**: ✅ Enabled (recommended for security)
7. **Require linear history**: ✅ Enabled (recommended for clean git history)
8. **Require deployments to succeed before merging**: ❌ Disabled (no deployments needed)

### Additional Settings

- **Do not allow bypassing the above settings**: ✅ Enabled
- **Restrict who can push to matching branches**: Configure based on your team structure

## GitHub CLI Setup (Alternative)

You can also set up branch protection using GitHub CLI:

```bash
gh api repos/:owner/:repo/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["Run Tests"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
  --field restrictions=null
```

## Verification

After setting up branch protection:

1. Create a test branch
2. Make a small change and create a PR
3. Verify all CI checks run and must pass before merging is allowed
4. Test that direct pushes to main are blocked

## Troubleshooting

### Common Issues

1. **Status checks not showing up**: Ensure the workflow has run at least once on the main branch
2. **Tests failing in CI but passing locally**: Check that the `ci` foundry profile is properly configured
3. **Permission issues**: Ensure GitHub Actions has sufficient permissions to run all checks

### Support

For issues with branch protection setup, check:
- GitHub Actions logs
- Repository settings permissions
- Required status check names match your workflow job names exactly
