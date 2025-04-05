

INSTALL_DIR="/{client_name}-odoo-17"
STAGING_DIR="$INSTALL_DIR/staging"
ADDONS_DIR="$INSTALL_DIR/addons"
GIT_CONFIG_FILE="$INSTALL_DIR/.git_config"
MAIN_BRANCH="main"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

usage() {
    echo -e "${BOLD}Git Panel for Odoo 17${NC}"
    echo -e "Provides git management functionality similar to odoo.sh\n"
    echo -e "${BOLD}Usage:${NC} $0 [action]"
    echo -e "${BOLD}Actions:${NC}"
    echo -e "  ${CYAN}setup${NC}         - Configure git repository for addons"
    echo -e "  ${CYAN}status${NC}        - Show git status for addons repository"
    echo -e "  ${CYAN}fetch${NC}         - Sync local repository with remote changes"
    echo -e "  ${CYAN}push${NC}          - Commit and push local changes to remote repository"
    echo -e "  ${CYAN}pull${NC} [branch] - Pull and merge changes from a branch"
    echo -e "  ${CYAN}list-branches${NC} - List all available branches"
    echo -e "  ${CYAN}help${NC}          - Show this help message"
    exit 1
}

check_git_installed() {
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Error: git is not installed${NC}"
        echo -e "Please install git using: sudo apt-get install git"
        exit 1
    fi
}

check_git_configured() {
    if [ -f "$GIT_CONFIG_FILE" ]; then
        return 0
    else
        return 1
    fi
}

load_git_config() {
    if [ -f "$GIT_CONFIG_FILE" ]; then
        source "$GIT_CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

save_git_config() {
    local repo_url=$1
    local username=$2
    
    echo "REPO_URL=\"$repo_url\"" > "$GIT_CONFIG_FILE"
    echo "USERNAME=\"$username\"" >> "$GIT_CONFIG_FILE"
    
    git config --global credential.helper store
    chmod 600 "$GIT_CONFIG_FILE"
}

setup_git_repository() {
    echo -e "${BOLD}Git Repository Setup${NC}"
    
    if check_git_configured; then
        load_git_config
        echo -e "${YELLOW}A git repository is already configured:${NC}"
        echo -e "Repository URL: ${CYAN}$REPO_URL${NC}"
        echo -e "Username: ${CYAN}$USERNAME${NC}"
        
        read -p "Do you want to reconfigure? (y/N): " reconfigure
        if [[ "$reconfigure" != "y" && "$reconfigure" != "Y" ]]; then
            return 0
        fi
    fi
    
    read -p "Enter GitHub repository URL (e.g., https://github.com/username/repo): " repo_url
    
    read -p "Enter GitHub username: " username
    
    echo "You will be prompted for your password/token when performing git operations."
    echo "This will be stored securely using git's credential helper."
    
    save_git_config "$repo_url" "$username"
    
    if [ ! -d "$ADDONS_DIR" ]; then
        mkdir -p "$ADDONS_DIR"
    fi
    
    if [ -d "$ADDONS_DIR/.git" ]; then
        echo -e "${YELLOW}The addons directory is already a git repository.${NC}"
        
        cd "$ADDONS_DIR"
        git remote set-url origin "https://$username:$token@${repo_url#https://}"
        
        echo -e "${GREEN}Repository URL updated successfully.${NC}"
    else
        echo -e "${BLUE}Initializing git repository in addons directory...${NC}"
        
        cd "$ADDONS_DIR"
        git init
        git remote add origin "https://$username:$token@${repo_url#https://}"
        
        if git ls-remote --heads origin | grep -q "$MAIN_BRANCH"; then
            echo -e "${BLUE}Fetching existing repository...${NC}"
            git fetch origin
            git checkout -b "$MAIN_BRANCH" "origin/$MAIN_BRANCH"
        else
            echo -e "${YELLOW}Repository appears to be empty. Creating initial commit...${NC}"
            if [ ! -f "README.md" ]; then
                echo "# Odoo 17 Custom Addons" > README.md
                echo "" >> README.md
                echo "This repository contains custom addons for Odoo 17." >> README.md
            fi
            
            if [ ! -f ".gitignore" ]; then
                echo "# Byte-compiled / optimized / DLL files" > .gitignore
                echo "__pycache__/" >> .gitignore
                echo "*.py[cod]" >> .gitignore
                echo "*$py.class" >> .gitignore
                echo "*.so" >> .gitignore
                echo "*.log" >> .gitignore
                echo ".DS_Store" >> .gitignore
            fi
            
            git add .
            git commit -m "Initial commit"
            git branch -M "$MAIN_BRANCH"
            git push -u origin "$MAIN_BRANCH"
        fi
        
        echo -e "${GREEN}Git repository setup completed successfully.${NC}"
    fi
    
    return 0
}

show_git_status() {
    if ! check_git_configured; then
        echo -e "${RED}Git repository not configured. Use 'setup' command first.${NC}"
        return 1
    fi
    
    load_git_config
    
    echo -e "${BOLD}Git Status${NC}"
    
    cd "$ADDONS_DIR"
    echo -e "${BLUE}Repository URL:${NC} $REPO_URL"
    echo -e "${BLUE}Current branch:${NC} $(git rev-parse --abbrev-ref HEAD)"
    echo -e "${BLUE}Status:${NC}"
    git status --short
    
    if [ -d "$STAGING_DIR" ]; then
        echo -e "\n${BOLD}Staging Environments:${NC}"
        for staging in "$STAGING_DIR"/*; do
            if [ -d "$staging" ]; then
                staging_name=$(basename "$staging")
                echo -e "${CYAN}$staging_name${NC} - Branch: $(get_staging_branch "$staging_name")"
            fi
        done
    fi
    
    return 0
}

fetch_remote_changes() {
    if ! check_git_configured; then
        echo -e "${RED}Git repository not configured. Use 'setup' command first.${NC}"
        return 1
    fi
    
    load_git_config
    
    echo -e "${BOLD}Fetching Remote Changes${NC}"
    
    cd "$ADDONS_DIR"
    git fetch --all
    
    echo -e "${GREEN}Remote changes fetched successfully.${NC}"
    return 0
}

push_local_changes() {
    if ! check_git_configured; then
        echo -e "${RED}Git repository not configured. Use 'setup' command first.${NC}"
        return 1
    fi
    
    load_git_config
    
    echo -e "${BOLD}Pushing Local Changes${NC}"
    
    cd "$ADDONS_DIR"
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    if git diff-index --quiet HEAD --; then
        echo -e "${YELLOW}No changes detected in working directory.${NC}"
    else
        echo -e "${BLUE}Changes to be committed:${NC}"
        git diff --stat
        
        read -p "Enter commit message: " commit_message
        if [ -z "$commit_message" ]; then
            commit_message="Update $(date +%Y-%m-%d)"
        fi
        
        git add .
        git commit -m "$commit_message"
        git push origin "$current_branch"
        
        echo -e "${GREEN}Changes pushed successfully.${NC}"
    fi
    
    return 0
}

pull_changes() {
    if ! check_git_configured; then
        echo -e "${RED}Git repository not configured. Use 'setup' command first.${NC}"
        return 1
    fi
    
    load_git_config
    
    echo -e "${BOLD}Pulling Changes${NC}"
    
    local source_branch=$1
    cd "$ADDONS_DIR"
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    if [ -z "$source_branch" ]; then
        source_branch="$MAIN_BRANCH"
    fi
    
    if ! git branch -r | grep -q "origin/$source_branch"; then
        echo -e "${RED}Error: Branch '$source_branch' does not exist in remote repository.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Pulling changes from '$source_branch' into '$current_branch'...${NC}"
    git pull origin "$source_branch"
    
    echo -e "${GREEN}Changes pulled successfully.${NC}"
    return 0
}

list_branches() {
    if ! check_git_configured; then
        echo -e "${RED}Git repository not configured. Use 'setup' command first.${NC}"
        return 1
    fi
    
    load_git_config
    
    echo -e "${BOLD}Available Branches${NC}"
    
    cd "$ADDONS_DIR"
    git fetch --all
    
    echo -e "${BLUE}Local branches:${NC}"
    git branch | sed 's/^\*/  -/'
    
    echo -e "\n${BLUE}Remote branches:${NC}"
    git branch -r | grep -v HEAD | sed "s/origin\//  - /"
    
    return 0
}

get_staging_branch() {
    local staging_name=$1
    if [ -f "$STAGING_DIR/$staging_name/.git_branch" ]; then
        cat "$STAGING_DIR/$staging_name/.git_branch"
    else
        echo "unknown"
    fi
}

check_git_installed

case "$1" in
    setup)
        setup_git_repository
        ;;
    status)
        show_git_status
        ;;
    fetch)
        fetch_remote_changes
        ;;
    push)
        push_local_changes
        ;;
    pull)
        pull_changes "$2"
        ;;
    list-branches)
        list_branches
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        ;;
esac

exit 0
