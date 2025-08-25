#!/bin/bash

echo "╔════════════════════════════════════════╗"
echo "║         TeXRA Auto-Setup v1.0         ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Check if we have configuration file
if [ -f "/tmp/texra-config.json" ]; then
    echo "📄 Found configuration file"
    CONFIG=$(cat /tmp/texra-config.json)
else
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
        
        # Check if we have Overleaf Codespace secrets
        if [ ! -z "$OVERLEAF_EMAIL" ] && [ ! -z "$OVERLEAF_TOKEN" ]; then
            echo "🔐 Using Overleaf Codespace secrets for authentication"
            EMAIL="$OVERLEAF_EMAIL"
            PASSWORD="$OVERLEAF_TOKEN"
        else
            read -p "📧 Email: " EMAIL
            read -s -p "🔑 Password: " PASSWORD
            echo ""
        fi
        
        # Extract project ID from various URL formats (24 hexadecimal characters)
        PROJECT_ID=$(echo "$PROJECT_URL" | grep -oE '[a-f0-9]{24}')
        if [ -z "$PROJECT_ID" ]; then
            echo "❌ Could not extract project ID from URL"
            echo "   Please ensure URL contains a 24-character project ID"
            exit 1
        fi
        
        echo "🔧 Configuring Git credential helper for Overleaf..."
        git config --global credential.helper store
        
        # URL-encode the email to handle special characters
        ENCODED_EMAIL=$(echo "$EMAIL" | sed 's/@/%40/g')
        
        # Store credentials before cloning
        echo "https://${ENCODED_EMAIL}:${PASSWORD}@git.overleaf.com" > ~/.git-credentials
        
        echo "📥 Cloning project ${PROJECT_ID}..."
        git clone "https://${ENCODED_EMAIL}:${PASSWORD}@git.overleaf.com/${PROJECT_ID}" /tmp/manual-repo
        
        if [ $? -eq 0 ]; then
            git config --global user.email "${EMAIL}"
            git config --global user.name "$(echo ${EMAIL} | cut -d'@' -f1)"
            echo "✅ Overleaf repository cloned successfully"
        else
            echo "❌ Failed to clone Overleaf repository"
            echo "   Please check your credentials and project URL"
        fi
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

# Utility function for JSON parsing with fallback
parse_json() {
    local key1="$1"
    local key2="$2"
    local default="${3:-}"
    
    # Try Python first (most reliable)
    if command -v python3 &> /dev/null; then
        local result=$(echo "$CONFIG" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Try first key, then fallback key, then default
    value = data.get('$key1', '')
    if not value and '$key2':
        value = data.get('$key2', '')
    print(value if value else '$default')
except:
    print('$default')
" 2>/dev/null)
        echo "${result:-$default}"
    elif command -v python &> /dev/null; then
        # Fallback to Python 2 if available
        local result=$(echo "$CONFIG" | python -c "
import sys, json
try:
    data = json.load(sys.stdin)
    value = data.get('$key1', '')
    if not value and '$key2':
        value = data.get('$key2', '')
    print value if value else '$default'
except:
    print '$default'
" 2>/dev/null)
        echo "${result:-$default}"
    else
        echo "⚠️  Warning: Python not available for JSON parsing" >&2
        echo "$default"
    fi
}

# Parse configuration with sensible defaults
REPO_URL=$(parse_json 'repoUrl' 'url' '')

# Check if we should use Codespace secrets for Overleaf
if [[ "$REPO_URL" == *"overleaf"* ]] && [ ! -z "$OVERLEAF_EMAIL" ] && [ ! -z "$OVERLEAF_TOKEN" ]; then
    echo "🔐 Using Overleaf Codespace secrets for authentication"
    USERNAME="$OVERLEAF_EMAIL"
    TOKEN="$OVERLEAF_TOKEN"
    GIT_EMAIL="$OVERLEAF_EMAIL"
    GIT_NAME=$(echo "$OVERLEAF_EMAIL" | cut -d'@' -f1)
else
    # Use credentials from JSON config
    USERNAME=$(parse_json 'username' 'user' '')  
    TOKEN=$(parse_json 'password' 'token' '')
    GIT_NAME=$(parse_json 'gitName' '' '')
    GIT_EMAIL=$(parse_json 'gitEmail' '' '')
fi

# For GitHub repos in Codespaces, use GitHub user info
if [[ "$REPO_URL" == *"github.com"* ]] && [ ! -z "$GITHUB_USER" ]; then
    if [ -z "$GIT_NAME" ]; then
        GIT_NAME="$GITHUB_USER"
    fi
    if [ -z "$GIT_EMAIL" ]; then
        # Try to get email from gh cli if available
        if command -v gh &> /dev/null && command -v python3 &> /dev/null; then
            GIT_EMAIL=$(gh api user 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    email = data.get('email', '')
    print(email if email else '')
except:
    pass
" 2>/dev/null)
        fi
        # Fallback to noreply email
        GIT_EMAIL="${GIT_EMAIL:-${GITHUB_USER}@users.noreply.github.com}"
    fi
    echo "🔧 Using GitHub user: $GIT_NAME"
fi

# Set defaults if still empty
if [ -z "$GIT_NAME" ]; then
    GIT_NAME="TeXRA User"
fi
if [ -z "$GIT_EMAIL" ]; then
    GIT_EMAIL="user@texra.ai"
fi

# Validate we have a repository URL
if [ -z "$REPO_URL" ]; then
    echo "❌ Error: No repository URL found in configuration"
    echo ""
    echo "Configuration file should contain:"
    echo '  {"repoUrl": "...", "username": "...", "password": "..."}'
    exit 1
fi

echo "📎 Repository: ${REPO_URL}"
echo ""

# Save .devcontainer for later
cp -r /workspaces/texra-workspace/.devcontainer /tmp/

# Clone based on repository type
if [[ "$REPO_URL" == *"overleaf"* ]]; then
    echo "📚 Detected Overleaf repository"
    # Extract project ID from various URL formats (24 hexadecimal characters)
    PROJECT_ID=$(echo "$REPO_URL" | grep -oE '[a-f0-9]{24}')
    
    if [ -z "$PROJECT_ID" ]; then
        echo "❌ Could not extract Overleaf project ID from URL"
        echo "   URL should contain a 24-character project ID"
        exit 1
    fi
    
    echo "🔧 Configuring Git credential helper for Overleaf..."
    git config --global credential.helper store
    
    # URL-encode the username/email to handle special characters
    ENCODED_USERNAME=$(echo "$USERNAME" | sed 's/@/%40/g')
    
    # Store credentials before cloning
    echo "https://${ENCODED_USERNAME}:${TOKEN}@git.overleaf.com" > ~/.git-credentials
    
    echo "📥 Cloning project ${PROJECT_ID}..."
    git clone "https://${ENCODED_USERNAME}:${TOKEN}@git.overleaf.com/${PROJECT_ID}" /tmp/user-repo 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Overleaf repository cloned successfully"
    else
        echo "❌ Failed to clone Overleaf repository"
        echo "   Please check your credentials and project URL"
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

# Configure git user info
git config --global user.name "${GIT_NAME}"
git config --global user.email "${GIT_EMAIL}"

# Clean up sensitive data
rm -rf /tmp/user-repo /tmp/.devcontainer /tmp/texra-config.json
unset TOKEN PASSWORD CONFIG

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
echo "   • PDFs are saved to ./build folder"
echo "   • .devcontainer is locally ignored"
echo ""
echo "🚀 Happy writing with TeXRA!"