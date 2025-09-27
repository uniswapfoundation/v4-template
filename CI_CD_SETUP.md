# CI/CD Pipeline Documentation

## Overview

This repository uses a comprehensive CI/CD pipeline to ensure code quality, security, and reliability before merging changes to the main branch.

## Pipeline Components

### 1. Lint and Format Check (`lint-and-format`)
- Runs `forge fmt --check` to ensure consistent code formatting
- Verifies contracts can build successfully
- **Required for**: All PRs and pushes

### 2. Unit Tests (`test`)
- Runs all unit tests with verbose output (`forge test -vvv`)
- Generates gas reports for analysis
- **Required for**: All PRs and pushes
- **Dependencies**: Must pass lint-and-format first

### 3. Test Coverage (`coverage`)
- Generates LCOV coverage reports
- Uploads coverage data to Codecov (if configured)
- **Required for**: All PRs and pushes
- **Dependencies**: Must pass lint-and-format first

### 4. Integration Tests (`integration-tests`)
- Starts local Anvil node for testing
- Runs position manager and perps hook integration tests
- Tests actual contract interactions
- **Required for**: All PRs and pushes
- **Dependencies**: Must pass unit tests first

### 5. Security Analysis (`security-analysis`)
- Runs Slither static analysis (if available)
- Performs automated security checks
- **Required for**: All PRs and pushes
- **Dependencies**: Must pass lint-and-format first

### 6. Stress Tests (`stress-tests`)
- Runs stress testing and edge case tests
- **Triggered only**: On pushes to main branch
- **Dependencies**: Must pass unit tests first

### 7. Gas Analysis (`gas-analysis`)
- Generates gas snapshots
- Compares gas usage for PRs
- **Required for**: All PRs and pushes
- **Dependencies**: Must pass unit tests first

## Local Development Workflow

### Prerequisites

1. Install Foundry:
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. Install pre-commit (optional but recommended):
   ```bash
   pip install pre-commit
   pre-commit install
   ```

### Development Commands

```bash
# Install dependencies and build
make build

# Run all tests locally
make test

# Run tests with verbose output
make test-verbose

# Run specific test suites
make test-position-manager
make test-perps-hook

# Check formatting
forge fmt --check

# Format code
forge fmt

# Generate gas report
make test-gas

# Generate coverage report
make coverage

# Clean build artifacts
make clean
```

### Pre-commit Hooks

The repository includes pre-commit hooks that run:
- Code formatting (`forge fmt`)
- Build validation (`forge build`)
- Basic tests on push (`forge test`)
- YAML validation
- File cleanup (trailing whitespace, etc.)

## Branch Protection Rules

### Main Branch Requirements

All changes to `main` must:
1. Be submitted via Pull Request
2. Pass ALL CI checks:
   - ✅ lint-and-format
   - ✅ test
   - ✅ coverage
   - ✅ integration-tests
   - ✅ security-analysis
   - ✅ gas-analysis
3. Receive at least 1 approving review
4. Have all conversations resolved

### Setting Up Branch Protection

See [.github/BRANCH_PROTECTION.md](.github/BRANCH_PROTECTION.md) for detailed setup instructions.

## Pull Request Guidelines

### PR Template

All PRs must use the provided template that covers:
- Description of changes
- Type of change (bugfix, feature, etc.)
- Testing performed
- Security considerations
- Gas impact analysis
- Breaking changes (if any)
- Documentation updates

### PR Checklist

Before submitting a PR:
- [ ] All tests pass locally
- [ ] Code is properly formatted (`forge fmt`)
- [ ] New functionality has tests
- [ ] Gas usage analyzed
- [ ] Security implications considered
- [ ] Documentation updated
- [ ] PR template completed

## Continuous Integration Details

### Foundry Profiles

The pipeline uses the `ci` profile defined in `foundry.toml`:
- Optimized for CI speed
- Reduced fuzz test runs (100 vs default)
- Gas reporting enabled
- Verbosity level 2

### Environment Variables

CI pipeline uses:
- `FOUNDRY_PROFILE=ci` for optimized testing
- Standard Anvil test accounts for integration tests
- Codecov token (if coverage upload is enabled)

### Artifacts

The pipeline generates and stores:
- Gas snapshots (`.gas-snapshot`)
- Coverage reports (`lcov.info`)
- Build artifacts

## Troubleshooting

### Common Issues

1. **Formatting failures**: Run `forge fmt` locally
2. **Test failures in CI but not locally**: Check Foundry version compatibility
3. **Gas snapshot differences**: Review changes for gas impact
4. **Integration test failures**: Ensure contracts build correctly
5. **Coverage issues**: Verify test completeness

### Debug Commands

```bash
# Check Foundry version
forge --version

# Run tests with CI profile locally
FOUNDRY_PROFILE=ci forge test

# Build with CI profile
FOUNDRY_PROFILE=ci forge build

# Generate gas snapshot locally
forge snapshot
```

### Getting Help

1. Check GitHub Actions logs for specific failure details
2. Run the failing command locally with the CI profile
3. Review the relevant documentation section
4. Check for recent changes in dependencies

## Monitoring and Maintenance

### Regular Tasks

1. **Update dependencies**: Regularly update Foundry and other tools
2. **Review gas snapshots**: Monitor for gas usage increases
3. **Update CI configurations**: Keep workflows current with best practices
4. **Review security reports**: Address any findings from static analysis

### Performance Optimization

The CI pipeline is optimized for:
- Fast feedback (parallel jobs where possible)
- Comprehensive coverage (multiple test types)
- Clear failure reporting (verbose output where needed)
- Minimal resource usage (reduced fuzz runs in CI)

## Security Considerations

The CI/CD pipeline includes:
- Static analysis for common vulnerabilities
- Gas usage monitoring to prevent DOS attacks
- Comprehensive test coverage requirements
- Code review requirements before merging

This ensures that all code changes are thoroughly vetted before reaching production.
