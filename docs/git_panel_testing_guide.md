# Git Panel Testing Guide

This guide outlines the testing methodology for the Git Panel feature in the Odoo 17 installer. The testing approach focuses on replicating real user behavior through well-defined initial states, specific actions, and expected end states.

## Testing Philosophy

Each test should document:
- **State A**: The initial state before the test
- **Action**: The specific action taken by the user
- **State B**: The expected end state after the action

This approach ensures comprehensive coverage of all possible user interactions with the git panel and helps identify any issues in the user experience.

## Prerequisites

Before beginning testing:
1. Ensure you have a GitHub account with a personal access token
2. Have a test repository available (either empty or with some content)
3. Have the Odoo 17 installer set up and working correctly
4. Ensure Docker is running and available

## Test Scenarios

### 1. Initial Setup Tests

#### Test 1.1: First-time Repository Detection
- **State A**: Fresh Odoo installation with no Git configuration
- **Action**: Run `./git_panel.sh setup`
- **State B**: User is prompted to enter GitHub repository URL, username, and token; configuration is saved to `.git_config` file

#### Test 1.2: Repository URL Validation
- **State A**: Git panel setup screen
- **Action**: Enter an invalid repository URL format
- **State B**: Error message displayed, prompting user to enter a valid URL

#### Test 1.3: Token Validation
- **State A**: Git panel setup with valid repository URL and username
- **Action**: Enter an invalid GitHub token
- **State B**: Error message displayed, prompting user to enter a valid token

#### Test 1.4: Environment Variable Token
- **State A**: Environment variable `jpinillagoshawk_github_token` set with valid token
- **Action**: Run `./git_panel.sh setup` with valid repository URL and username
- **State B**: Token is automatically detected from environment variable, no prompt for token

### 2. Git Status Tests

#### Test 2.1: Repository Status Display
- **State A**: Configured Git repository with some files
- **Action**: Run `./git_panel.sh status`
- **State B**: Displays current branch, repository URL, and status of files (modified, untracked, etc.)

#### Test 2.2: Staging Environment Status
- **State A**: Configured Git repository with staging environments
- **Action**: Run `./git_panel.sh status`
- **State B**: Displays current branch, repository URL, file status, and list of staging environments with their associated branches

### 3. Fetch Tests

#### Test 3.1: Fetching Remote Changes
- **State A**: Local repository behind remote repository
- **Action**: Run `./git_panel.sh fetch`
- **State B**: Remote changes are fetched, success message displayed

#### Test 3.2: Fetch with Invalid Token
- **State A**: Configured repository with invalid or expired token
- **Action**: Run `./git_panel.sh fetch`
- **State B**: Error message displayed, prompting user to enter a valid token

### 4. Push Tests

#### Test 4.1: Push with No Changes
- **State A**: Repository with no local changes
- **Action**: Run `./git_panel.sh push`
- **State B**: Message indicating no changes to push

#### Test 4.2: Push with Local Changes
- **State A**: Repository with local changes
- **Action**: Run `./git_panel.sh push`
- **State B**: Displays list of changed files with +X -Y format, prompts for commit message, pushes changes to remote

#### Test 4.3: Push Confirmation
- **State A**: Repository with local changes, push confirmation prompt
- **Action**: Answer "N" to confirmation prompt
- **State B**: Push operation cancelled, local changes remain uncommitted

### 5. Pull Tests

#### Test 5.1: Branch Selection
- **State A**: Repository with multiple branches
- **Action**: Run `./git_panel.sh pull`
- **State B**: Displays numbered list of branches, prompts user to select source branch

#### Test 5.2: Pull with Uncommitted Changes
- **State A**: Repository with uncommitted local changes
- **Action**: Run `./git_panel.sh pull`, select a branch
- **State B**: Warning about uncommitted changes, prompt to continue or cancel

#### Test 5.3: Pull with Conflicts
- **State A**: Repository with changes that conflict with remote
- **Action**: Run `./git_panel.sh pull`, select a branch with conflicts
- **State B**: Error message about conflicts, pull operation fails

### 6. Branch Management Tests

#### Test 6.1: List Branches
- **State A**: Repository with multiple branches
- **Action**: Run `./git_panel.sh list-branches`
- **State B**: Displays list of local and remote branches

#### Test 6.2: Create Staging with Branch
- **State A**: Fresh Odoo installation with configured Git repository
- **Action**: Run `./staging.sh create staging-test`
- **State B**: Creates staging environment and corresponding git branch from main

#### Test 6.3: Delete Staging with Branch
- **State A**: Staging environment with associated git branch
- **Action**: Run `./staging.sh delete staging-test`
- **State B**: Deletes staging environment and corresponding git branch

#### Test 6.4: Delete Staging with Uncommitted Changes
- **State A**: Staging environment with uncommitted changes in associated branch
- **Action**: Run `./staging.sh delete staging-test`
- **State B**: Warning about uncommitted changes, prompt to continue or cancel

### 7. Interactive Menu Tests

#### Test 7.1: Main Menu Navigation
- **State A**: Fresh terminal
- **Action**: Run `./git_panel.sh` without arguments
- **State B**: Displays interactive menu with options for setup, status, fetch, push, pull, and list branches

#### Test 7.2: Menu Option Selection
- **State A**: Interactive menu displayed
- **Action**: Select option 1 (Setup)
- **State B**: Executes setup function, returns to menu after completion

#### Test 7.3: Exit Menu
- **State A**: Interactive menu displayed
- **Action**: Select option 0 (Exit)
- **State B**: Exits the git panel script

### 8. Edge Cases

#### Test 8.1: No Internet Connection
- **State A**: Repository configured, no internet connection
- **Action**: Run `./git_panel.sh fetch`
- **State B**: Appropriate error message about connection failure

#### Test 8.2: Repository URL Changed
- **State A**: Repository configured with URL A
- **Action**: Run `./git_panel.sh setup` and change to URL B
- **State B**: Configuration updated with new URL, remote URL updated in git config

## Troubleshooting Common Issues

### Authentication Failures
- Verify GitHub token has correct permissions (repo scope)
- Check if token has expired
- Ensure username matches the token owner

### Connection Issues
- Verify internet connectivity
- Check if GitHub is accessible
- Ensure no firewall is blocking git operations

### Branch Management Issues
- Verify main branch exists in remote repository
- Check if user has write permissions to the repository
- Ensure no branch name conflicts exist

## Test Results Documentation

For each test, document:
1. Test ID and name
2. Date and time of test
3. Test result (Pass/Fail)
4. Any unexpected behavior
5. Screenshots or logs if applicable

This documentation helps track progress and identify patterns in issues that may arise during testing.
