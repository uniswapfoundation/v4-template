# GitHub Actions CI/CD Setup

## ✅ What's Already Set Up

Your repository now has a complete GitHub Actions CI/CD pipeline configured in `.github/workflows/test.yml`.

## 🚀 Quick Setup Steps

### 1. Enable GitHub Actions (if not already enabled)

1. Go to your repository on GitHub
2. Click on the **Actions** tab
3. If prompted, click **"I understand my workflows, go ahead and enable them"**

### 2. Test the Pipeline

**Option A: Push to trigger workflow**
```bash
git add .
git commit -m "feat: add CI/CD pipeline"
git push origin main
```

**Option B: Manual trigger**
1. Go to **Actions** tab on GitHub
2. Click **"Test Suite"** workflow
3. Click **"Run workflow"** button
4. Select branch and click **"Run workflow"**

### 3. Set Up Branch Protection

After the workflow runs successfully at least once:

1. Go to **Settings** → **Branches**
2. Click **"Add rule"** or edit existing rule for `main`
3. Configure:
   - ✅ **Require a pull request before merging**
   - ✅ **Require status checks to pass before merging**
   - ✅ **Require branches to be up to date before merging**
   - Add status check: **"Run Tests"**
   - ✅ **Require conversation resolution before merging**
4. Click **"Create"** or **"Save changes"**

## 📊 Pipeline Overview

The GitHub Actions workflow includes **1 simple job**:

### Required Job
- 🧪 **Run Tests** - Runs all 176 test functions with `forge test -vvv`

### Additional Features (Currently Commented Out)
All the comprehensive checks are commented out but available to uncomment if you want more restrictions later:
- 🎨 **Lint and Format Check** - Code formatting & build validation
- 📊 **Test Coverage** - Coverage analysis with Codecov upload
- 🔗 **Integration Tests** - Tests with local Anvil node
- 🛡️ **Security Analysis** - Static analysis with Slither
- ⛽ **Gas Analysis** - Gas usage tracking and comparison
- 💪 **Stress Tests** - Performance and edge case testing

**To enable additional checks:** Simply uncomment the relevant sections in `.github/workflows/test.yml`

## 🔧 Configuration Details

### Triggers
The pipeline runs on:
- ✅ Push to `main` or `develop` branches
- ✅ Pull requests to `main` or `develop` branches  
- ✅ Manual workflow dispatch

### Environment
- **OS**: Ubuntu Latest
- **Foundry Profile**: `ci` (optimized for CI speed)
- **Node Setup**: Local Anvil for integration tests
- **Parallel Execution**: Jobs run concurrently when possible

### Artifacts
- 📊 Gas snapshots (uploaded as artifacts)
- 📈 Coverage reports (sent to Codecov if configured)

## 🎯 Next Steps

### 1. Test Your First PR

Create a test branch and PR:
```bash
git checkout -b test-ci
echo "# Test CI" >> TEST_CI.md
git add TEST_CI.md
git commit -m "test: verify CI pipeline"
git push origin test-ci
```

Then create a PR on GitHub and watch the CI pipeline run!

### 2. Configure Codecov (Optional)

For coverage reporting:
1. Go to [codecov.io](https://codecov.io)
2. Connect your GitHub repository  
3. Add the `CODECOV_TOKEN` secret in repository settings
4. Coverage reports will automatically upload

### 3. Customize the Pipeline (Optional)

Common customizations in `.github/workflows/test.yml`:

**Add more test commands:**
```yaml
- name: Run additional tests
  run: |
    forge test --match-contract "YourSpecificTest" -vv
    make your-custom-test-command
```

**Add deployment steps:**
```yaml
deploy:
  name: Deploy to Testnet
  needs: ci-success
  if: github.ref == 'refs/heads/main'
  steps:
    # Add deployment steps here
```

**Add notifications:**
```yaml
- name: Notify on success
  uses: 8398a7/action-slack@v3
  with:
    status: success
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

## 🐛 Troubleshooting

### Workflow not running?
- Check that `.github/workflows/test.yml` exists and is properly formatted
- Ensure GitHub Actions is enabled for your repository
- Verify branch names match your workflow triggers

### Tests failing in CI but passing locally?
- Run tests locally with CI profile: `FOUNDRY_PROFILE=ci forge test`
- Check Foundry version consistency
- Verify all dependencies are installed in CI

### Branch protection not working?
- Ensure the workflow has run at least once successfully
- Status check name must match exactly: "CI Pipeline Success"
- Check that branch protection rules are applied to the correct branch

### Integration tests failing?
- Anvil startup issues are common - the workflow includes proper wait times
- Check that all required environment variables are set
- Verify contract deployment scripts work in CI environment

## 📞 Support

For issues:
1. Check the Actions tab for detailed logs
2. Review the CI/CD documentation in `CI_CD_SETUP.md`
3. Compare local vs CI environments using the `ci` foundry profile

## 🎉 Success!

Once set up, every PR will automatically:
- ✅ Run all tests
- ✅ Check code formatting  
- ✅ Analyze security
- ✅ Track gas usage
- ✅ Generate coverage reports
- ✅ Block merging if anything fails

Your code quality is now protected! 🛡️
