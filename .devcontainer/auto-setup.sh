#!/bin/bash

echo "╔════════════════════════════════════════╗"
echo "║         TeXRA Auto-Setup v1.0         ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Check if we have configuration
if [ -z "$TEXRA_CONFIG" ]; then
    echo "ℹ️  No auto-configuration detected."
    echo ""
    echo "To manually set up your repository, run:"
    echo "  texra-setup"
    echo ""
    echo "Or visit texra.ai/launch to get started automatically."
    
    # Create helper script for manual setup
    cat > /usr/local/bin/texra-setup << 'MANUAL_SETUP'
#!/bin/bash
echo "🚀 TeXRA Manual Setup"
echo "===================="
echo ""
echo "Select repository type:"
echo "1) GitHub (Public)"
echo "2) GitHub (Private)"
echo "3) Overleaf"
echo ""
read -p "Enter choice (1-3): " choice

case $choice in
    1)
        read -p "📎 Repository URL: " REPO_URL
        git clone "$REPO_URL" /tmp/manual-repo
        ;;
    2)
        echo "🔐 Authenticating with GitHub..."
        gh auth login
        read -p "📎 Repository URL: " REPO_URL
        gh repo clone "$REPO_URL" /tmp/manual-repo
        ;;
    3)
        read -p "📎 Overleaf Project URL: " PROJECT_URL
        read -p "📧 Email: " EMAIL
        read -s -p "🔑 Password: " PASSWORD
        echo ""
        PROJECT_ID=$(echo "$PROJECT_URL" | grep -oP '(?<=project/)[a-z0-9]+')
        git clone "https://${EMAIL}:${PASSWORD}@git.overleaf.com/${PROJECT_ID}" /tmp/manual-repo
        git config --global credential.helper store
        echo "https://${EMAIL}:${PASSWORD}@git.overleaf.com" > ~/.git-credentials
        ;;
esac

# Move to workspace
if [ -d "/tmp/manual-repo" ]; then
    cp -r /workspaces/texra-workspace/.devcontainer /tmp/
    find /workspaces/texra-workspace -mindepth 1 -maxdepth 1 ! -name '.devcontainer' -exec rm -rf {} +
    mv /tmp/manual-repo/* /tmp/manual-repo/.[^.]* /workspaces/texra-workspace/ 2>/dev/null
    rm -rf /workspaces/texra-workspace/.devcontainer
    mv /tmp/.devcontainer /workspaces/texra-workspace/
    mkdir -p /workspaces/texra-workspace/.git/info
    echo ".devcontainer" >> /workspaces/texra-workspace/.git/info/exclude
    echo ".vscode" >> /workspaces/texra-workspace/.git/info/exclude
    rm -rf /tmp/manual-repo /tmp/.devcontainer
    echo "✅ Repository ready at /workspaces/texra-workspace"
fi
MANUAL_SETUP
    
    chmod +x /usr/local/bin/texra-setup
    exit 0
fi

echo "📦 Auto-configuring your repository..."

# Decode configuration
CONFIG=$(echo "$TEXRA_CONFIG" | base64 -d)
REPO_URL=$(echo "$CONFIG" | jq -r '.url')
USERNAME=$(echo "$CONFIG" | jq -r '.user // empty')
TOKEN=$(echo "$CONFIG" | jq -r '.token // empty')

echo "📎 Repository: ${REPO_URL}"
echo ""

# Save .devcontainer for later
cp -r /workspaces/texra-workspace/.devcontainer /tmp/

# Clone based on repository type
if [[ "$REPO_URL" == *"overleaf"* ]]; then
    echo "📚 Detected Overleaf repository"
    PROJECT_ID=$(echo "$REPO_URL" | grep -oP '(?<=project/)[a-z0-9]+')
    
    echo "🔐 Cloning with authentication..."
    git clone "https://${USERNAME}:${TOKEN}@git.overleaf.com/${PROJECT_ID}" /tmp/user-repo 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Setup Overleaf credentials for future pushes
        git config --global credential.helper store
        echo "https://${USERNAME}:${TOKEN}@git.overleaf.com" > ~/.git-credentials
        echo "✅ Overleaf authentication configured"
    else
        echo "❌ Failed to clone Overleaf repository"
        exit 1
    fi
    
elif [ ! -z "$TOKEN" ]; then
    echo "🔐 Detected private GitHub repository"
    CLEAN_URL=$(echo "$REPO_URL" | sed 's|https://||')
    
    echo "🔐 Cloning with authentication..."
    git clone "https://${USERNAME}:${TOKEN}@${CLEAN_URL}" /tmp/user-repo 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Setup GitHub credentials for future pushes
        git config --global credential.helper store
        echo "https://${USERNAME}:${TOKEN}@github.com" > ~/.git-credentials
        git config --global user.name "${USERNAME}"
        echo "✅ GitHub authentication configured"
    else
        echo "❌ Failed to clone private repository"
        exit 1
    fi
    
else
    echo "📂 Detected public repository"
    echo "📥 Cloning..."
    git clone "$REPO_URL" /tmp/user-repo 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to clone repository"
        exit 1
    fi
fi

# Clear workspace (except .devcontainer)
echo "🧹 Preparing workspace..."
find /workspaces/texra-workspace -mindepth 1 -maxdepth 1 ! -name '.devcontainer' -exec rm -rf {} +

# Move user repository to workspace root
echo "📂 Setting up your project..."
mv /tmp/user-repo/* /tmp/user-repo/.[^.]* /workspaces/texra-workspace/ 2>/dev/null

# Restore .devcontainer
rm -rf /workspaces/texra-workspace/.devcontainer
mv /tmp/.devcontainer /workspaces/texra-workspace/

# Add .devcontainer to local git exclude (not tracked in repo!)
mkdir -p /workspaces/texra-workspace/.git/info
echo "# TeXRA local excludes" >> /workspaces/texra-workspace/.git/info/exclude
echo ".devcontainer" >> /workspaces/texra-workspace/.git/info/exclude
echo ".vscode" >> /workspaces/texra-workspace/.git/info/exclude

# Clean up sensitive data
rm -rf /tmp/user-repo /tmp/.devcontainer
unset TEXRA_CONFIG TOKEN PASSWORD

# Show summary
echo ""
echo "╔════════════════════════════════════════╗"
echo "║         ✅ Setup Complete!             ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "📂 Your project is at: /workspaces/texra-workspace"
echo "📝 You can now:"
echo "   • Edit your LaTeX files"
echo "   • Use TeXRA AI features"
echo "   • Run 'git commit' and 'git push'"
echo ""
echo "💡 Tips:"
echo "   • Press Ctrl+S to auto-compile LaTeX"
echo "   • PDFs are saved to ./PDF folder"
echo "   • .devcontainer is locally ignored"
echo ""
echo "🚀 Happy writing with TeXRA!"