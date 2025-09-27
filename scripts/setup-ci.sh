#!/bin/bash

# CI/CD Setup Script for uniPerp
# This script helps set up the development environment with CI/CD tools

set -e

echo "🚀 Setting up uniPerp CI/CD environment..."

# Check if running on macOS or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "📱 Detected macOS"
    INSTALL_CMD="brew install"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "🐧 Detected Linux"
    INSTALL_CMD="sudo apt-get install -y"
else
    echo "❌ Unsupported OS: $OSTYPE"
    exit 1
fi

# Check if Foundry is installed
if ! command -v forge &> /dev/null; then
    echo "🔧 Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    source ~/.bashrc || source ~/.zshrc || true
    foundryup
else
    echo "✅ Foundry is already installed"
    forge --version
fi

# Install pre-commit if not present
if ! command -v pre-commit &> /dev/null; then
    echo "🪝 Installing pre-commit..."
    if command -v pip3 &> /dev/null; then
        pip3 install pre-commit
    elif command -v pip &> /dev/null; then
        pip install pre-commit
    else
        echo "❌ pip not found. Please install Python and pip first"
        exit 1
    fi
else
    echo "✅ pre-commit is already installed"
fi

# Install pre-commit hooks
echo "🔧 Setting up pre-commit hooks..."
pre-commit install
pre-commit install --hook-type pre-push

# Install Foundry dependencies
echo "📦 Installing Foundry dependencies..."
forge install --shallow

# Build contracts
echo "🏗️  Building contracts..."
forge build

# Run initial tests
echo "🧪 Running initial test suite..."
forge test

# Check formatting
echo "📝 Checking code formatting..."
forge fmt --check || {
    echo "⚠️  Code formatting issues detected. Running formatter..."
    forge fmt
    echo "✅ Code formatted"
}

# Generate gas snapshot
echo "⛽ Generating initial gas snapshot..."
forge snapshot

# Create .env template if it doesn't exist
if [ ! -f .env ]; then
    echo "📄 Creating .env template..."
    make create-env
fi

echo ""
echo "🎉 CI/CD setup completed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Set up branch protection rules (see .github/BRANCH_PROTECTION.md)"
echo "2. Configure Codecov if you want coverage reports"
echo "3. Review and customize the CI/CD workflow if needed"
echo "4. Create your first PR to test the pipeline!"
echo ""
echo "🛠️  Useful commands:"
echo "  make test          - Run all tests"
echo "  make test-verbose  - Run tests with verbose output"
echo "  forge fmt          - Format code"
echo "  make coverage      - Generate coverage report"
echo "  make help          - See all available commands"
echo ""
echo "📚 Documentation:"
echo "  - CI/CD Setup: CI_CD_SETUP.md"
echo "  - Branch Protection: .github/BRANCH_PROTECTION.md"
echo "  - Makefile help: make help"
