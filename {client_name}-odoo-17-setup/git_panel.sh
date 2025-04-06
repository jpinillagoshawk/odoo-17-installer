


INSTALL_DIR="/home/ubuntu/repos/rincondelmotor-odoo-17"
STAGING_DIR="$INSTALL_DIR/staging"
ADDONS_DIR="$INSTALL_DIR/addons"
GIT_CONFIG_FILE="$INSTALL_DIR/.git_config"
MAIN_BRANCH="main"
TOKEN_ENV_VAR="jpinillagoshawk_github_token"

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
    local token=$3
    
    echo "REPO_URL=\"$repo_url\"" > "$GIT_CONFIG_FILE"
    echo "USERNAME=\"$username\"" >> "$GIT_CONFIG_FILE"
    
    if [ -n "$token" ]; then
        echo "TOKEN=\"$token\"" >> "$GIT_CONFIG_FILE"
    fi
    
    git config --global credential.helper store
    chmod 600 "$GIT_CONFIG_FILE"
}

get_github_token() {
    token=${!TOKEN_ENV_VAR:-}
    
    if [ -n "$token" ]; then
        echo -e "${GREEN}Using GitHub token from environment variable.${NC}"
        return 0
    fi
    
    if [ -f "$GIT_CONFIG_FILE" ] && grep -q "TOKEN=" "$GIT_CONFIG_FILE"; then
        source "$GIT_CONFIG_FILE"
        if [ -n "$TOKEN" ]; then
            token="$TOKEN"
            echo -e "${GREEN}Using GitHub token from saved configuration.${NC}"
            return 0
        fi
    fi
    
    echo -e "${YELLOW}GitHub token not found in environment or configuration.${NC}"
    read -sp "Enter GitHub token: " token
    echo
    
    if [ -z "$token" ]; then
        echo -e "${RED}Error: GitHub token is required.${NC}"
        return 1
    fi
    
    return 0
}

validate_github_token() {
    local username=$1
    local token=$2
    
    echo -e "${BLUE}Validating GitHub token...${NC}"
    
    if curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $token" "https://api.github.com/user" | grep -q "200"; then
        echo -e "${GREEN}GitHub token is valid.${NC}"
        return 0
    else
        echo -e "${RED}Error: Invalid GitHub token.${NC}"
        return 1
    fi
}

parse_repo_url() {
    local repo_url=$1
    
    repo_domain=$(echo "$repo_url" | sed -E 's|https?://([^/]+)/.*|\1|')
    repo_path=$(echo "$repo_url" | sed -E 's|https?://[^/]+/(.*)|\1|')
    
    if [ -z "$repo_domain" ] || [ -z "$repo_path" ]; then
        echo -e "${RED}Error: Invalid repository URL format.${NC}"
        return 1
    fi
    
    return 0
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
    
    if [ -z "$repo_url" ]; then
        echo -e "${RED}Error: Repository URL is required.${NC}"
        return 1
    fi
    
    if ! parse_repo_url "$repo_url"; then
        return 1
    fi
    
    read -p "Enter GitHub username: " username
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: GitHub username is required.${NC}"
        return 1
    fi
    
    if ! get_github_token; then
        return 1
    fi
    
    if ! validate_github_token "$username" "$token"; then
        return 1
    fi
    
    save_git_config "$repo_url" "$username" "$token"
    
    if [ ! -d "$ADDONS_DIR" ]; then
        mkdir -p "$ADDONS_DIR"
    fi
    
    if [ -d "$ADDONS_DIR/.git" ]; then
        echo -e "${YELLOW}The addons directory is already a git repository.${NC}"
        
        cd "$ADDONS_DIR"
        git remote set-url origin "https://$username:$token@$repo_domain/$repo_path"
        
        echo -e "${GREEN}Repository URL updated successfully.${NC}"
    else
        echo -e "${BLUE}Initializing git repository in addons directory...${NC}"
        
        cd "$ADDONS_DIR"
        git init
        git remote add origin "https://$username:$token@$repo_domain/$repo_path"
        
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
    
    if ! get_github_token; then
        return 1
    fi
    
    git fetch --all
    
    echo -e "${GREEN}Remote changes fetched successfully.${NC}"
    return 0
}

select_branch() {
    local prompt=$1
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    local branches=()
    local i=1
    
    echo -e "${BOLD}$prompt${NC}"
    
    git fetch --all > /dev/null 2>&1
    
    while read -r branch; do
        branches+=("$branch")
        echo -e "${i}. ${CYAN}$branch${NC} $([ "$branch" = "$current_branch" ] && echo '[current]')"
        i=$((i+1))
    done < <(git branch | sed 's/^\*\s*//' | sort)
    
    while read -r branch; do
        skip=0
        for local_branch in "${branches[@]}"; do
            if [ "$local_branch" = "$branch" ]; then
                skip=1
                break
            fi
        done
        if [ $skip -eq 1 ]; then
            continue
        fi
        
        branches+=("$branch")
        echo -e "${i}. ${CYAN}$branch${NC} [remote]"
        i=$((i+1))
    done < <(git branch -r | grep -v HEAD | sed "s/origin\///" | sort)
    
    echo -e "${i}. ${YELLOW}Return to main menu${NC}"
    
    while true; do
        read -p "Select branch (1-$i): " choice
        
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Please enter a number.${NC}"
            continue
        fi
        
        if [ "$choice" -eq "$i" ]; then
            return 1
        fi
        
        if [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            selected_branch="${branches[$((choice-1))]}"
            echo -e "Selected branch: ${CYAN}$selected_branch${NC}"
            return 0
        else
            echo -e "${RED}Invalid selection. Please choose a number between 1 and $i.${NC}"
        fi
    done
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
        return 0
    else
        echo -e "${BLUE}Changes to be committed:${NC}"
        
        git diff --stat | while read -r line; do
            if [[ $line =~ ([0-9]+)[[:space:]]+insertion ]]; then
                insertions="${BASH_REMATCH[1]}"
            else
                insertions=0
            fi
            
            if [[ $line =~ ([0-9]+)[[:space:]]+deletion ]]; then
                deletions="${BASH_REMATCH[1]}"
            else
                deletions=0
            fi
            
            if [[ $line =~ \|[[:space:]]+[0-9]+ ]]; then
                file_name=$(echo "$line" | awk '{print $1}')
                echo -e "${file_name} | ${GREEN}+${insertions}${NC} ${RED}-${deletions}${NC}"
            else
                echo -e "$line"
            fi
        done
        
        read -p "Do you want to commit and push these changes? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "${YELLOW}Operation cancelled.${NC}"
            return 0
        fi
        
        read -p "Enter commit message: " commit_message
        if [ -z "$commit_message" ]; then
            commit_message="Update $(date +%Y-%m-%d)"
        fi
        
        git add .
        git commit -m "$commit_message"
        
        if ! get_github_token; then
            return 1
        fi
        
        echo -e "${BLUE}Pushing to remote repository...${NC}"
        if git push origin "$current_branch"; then
            echo -e "${GREEN}Changes pushed successfully.${NC}"
        else
            echo -e "${RED}Failed to push changes.${NC}"
            return 1
        fi
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
    
    cd "$ADDONS_DIR"
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    if ! select_branch "Select source branch to pull from:"; then
        return 0
    fi
    
    source_branch="$selected_branch"
    
    echo -e "${BLUE}Pulling changes from '$source_branch' into '$current_branch'...${NC}"
    
    if ! git diff-index --quiet HEAD --; then
        echo -e "${YELLOW}Warning: You have uncommitted changes in your working directory.${NC}"
        echo -e "It's recommended to commit or stash your changes before pulling."
        read -p "Do you want to continue anyway? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "${YELLOW}Pull cancelled.${NC}"
            return 0
        fi
    fi
    
    if ! get_github_token; then
        return 1
    fi
    
    if git pull origin "$source_branch"; then
        echo -e "${GREEN}Changes pulled successfully.${NC}"
    else
        echo -e "${RED}Failed to pull changes. There might be conflicts.${NC}"
        return 1
    fi
    
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
    
    if ! get_github_token; then
        return 1
    fi
    
    git fetch --all > /dev/null 2>&1
    
    echo -e "${BLUE}Local branches:${NC}"
    git branch | sed 's/^\*/  -/'
    
    echo -e "\n${BLUE}Remote branches:${NC}"
    git branch -r | grep -v HEAD | sed "s/origin\//  - /"
    
    read -p "Press Enter to continue..."
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

show_main_menu() {
    clear
    echo -e "${BOLD}===============================${NC}"
    echo -e "${BOLD}     Git Panel for Odoo 17     ${NC}"
    echo -e "${BOLD}===============================${NC}"
    echo -e "Provides git management functionality similar to odoo.sh\n"
    
    local current_branch=""
    if check_git_configured; then
        load_git_config
        cd "$ADDONS_DIR"
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
        echo -e "Repository: ${CYAN}$REPO_URL${NC}"
        echo -e "Current branch: ${CYAN}$current_branch${NC}\n"
    else
        echo -e "${YELLOW}Git repository not configured.${NC}\n"
    fi
    
    echo -e "${BOLD}Actions:${NC}"
    echo -e "1. ${CYAN}Setup${NC} - Configure git repository for addons"
    echo -e "2. ${CYAN}Status${NC} - Show git status for addons repository"
    echo -e "3. ${CYAN}Fetch${NC} - Sync local repository with remote changes"
    echo -e "4. ${CYAN}Push${NC} - Commit and push local changes to remote repository"
    echo -e "5. ${CYAN}Pull${NC} - Pull and merge changes from a branch"
    echo -e "6. ${CYAN}List Branches${NC} - List all available branches"
    echo -e "0. ${CYAN}Exit${NC} - Exit git panel"
    
    echo
    read -p "Enter your choice (0-6): " choice
    
    case "$choice" in
        1)
            setup_git_repository
            ;;
        2)
            show_git_status
            ;;
        3)
            fetch_remote_changes
            ;;
        4)
            push_local_changes
            ;;
        5)
            pull_changes
            ;;
        6)
            list_branches
            ;;
        0)
            echo -e "${GREEN}Exiting Git Panel.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            ;;
    esac
    
    read -p "Press Enter to continue..."
    show_main_menu
}

check_git_installed

if [ $# -eq 0 ]; then
    show_main_menu
else
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
            if [ -n "$2" ]; then
                selected_branch="$2"
                pull_changes
            else
                pull_changes
            fi
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
fi

exit 0
