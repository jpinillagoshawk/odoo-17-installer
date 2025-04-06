# Git Panel Testing Guide

## Overview
This document provides a comprehensive guide for testing the Git Panel feature in the Odoo 17 installer. The Git Panel allows users to manage Git repositories for their Odoo addons, similar to how Odoo.sh works, without having to manually type each Git command.

## Testing Philosophy
Each test should replicate a real user's behavior by:
1. Starting from a well-defined initial state (State A)
2. Performing specific actions
3. Verifying the expected end state (State B)

## Prerequisites
- A fresh installation of the Odoo 17 installer
- Git installed on the system
- A GitHub account with a test repository
- A valid GitHub personal access token with repo permissions

## Test Scenarios

### 1. Initial Setup Tests

#### Test 1.1: First-time Repository Setup
**State A:** Fresh Odoo installation with no Git configuration
**Actions:**
1. Run `./git_panel.sh setup`
2. Enter a valid GitHub repository URL (e.g., https://github.com/username/repo)
3. Enter GitHub username
4. Enter GitHub token when prompted

**State B:**
- `.git_config` file created in the installation directory
- Addons directory initialized as a Git repository
- Remote origin set to the provided GitHub URL
- Main branch checked out if it exists, or created if the repository is empty

#### Test 1.2: Reconfiguration of Existing Repository
**State A:** Odoo installation with Git already configured
**Actions:**
1. Run `./git_panel.sh setup`
2. Confirm reconfiguration when prompted
3. Enter new GitHub repository URL
4. Enter GitHub username
5. Enter GitHub token when prompted

**State B:**
- `.git_config` file updated with new repository information
- Remote origin updated to the new GitHub URL

#### Test 1.3: Invalid Repository URL
**State A:** Fresh Odoo installation with no Git configuration
**Actions:**
1. Run `./git_panel.sh setup`
2. Enter an invalid GitHub repository URL (e.g., github.com/username/repo)
3. Enter GitHub username
4. Enter GitHub token when prompted

**State B:**
- Error message displayed about invalid URL format
- Setup process halted or prompting for correct URL

#### Test 1.4: Invalid Credentials
**State A:** Fresh Odoo installation with no Git configuration
**Actions:**
1. Run `./git_panel.sh setup`
2. Enter a valid GitHub repository URL
3. Enter GitHub username
4. Enter invalid GitHub token when prompted

**State B:**
- Error message displayed about authentication failure
- Setup process halted or prompting for correct credentials

### 2. Git Status Tests

#### Test 2.1: Clean Repository Status
**State A:** Odoo installation with Git configured and no changes
**Actions:**
1. Run `./git_panel.sh status`

**State B:**
- Display shows repository URL
- Display shows current branch
- Display shows "working tree clean" or equivalent
- If staging environments exist, they are listed with their associated branches

#### Test 2.2: Modified Files Status
**State A:** Odoo installation with Git configured and modified files
**Actions:**
1. Modify a file in the addons directory
2. Run `./git_panel.sh status`

**State B:**
- Display shows repository URL
- Display shows current branch
- Display shows modified files with "M" prefix
- If staging environments exist, they are listed with their associated branches

#### Test 2.3: Untracked Files Status
**State A:** Odoo installation with Git configured and new untracked files
**Actions:**
1. Create a new file in the addons directory
2. Run `./git_panel.sh status`

**State B:**
- Display shows repository URL
- Display shows current branch
- Display shows untracked files with "??" prefix
- If staging environments exist, they are listed with their associated branches

### 3. Fetch/Pull/Push Tests

#### Test 3.1: Fetch Remote Changes
**State A:** Odoo installation with Git configured and remote changes available
**Actions:**
1. Make changes to the remote repository (through GitHub web interface)
2. Run `./git_panel.sh fetch`

**State B:**
- Display shows "Remote changes fetched successfully"
- Local repository has fetched the remote changes (verify with `git log origin/main`)

#### Test 3.2: Pull Changes from Main Branch
**State A:** Odoo installation with Git configured and remote changes available
**Actions:**
1. Make changes to the remote repository (through GitHub web interface)
2. Run `./git_panel.sh pull`

**State B:**
- Display shows "Changes pulled successfully"
- Local repository has incorporated the remote changes (verify with `git log`)

#### Test 3.3: Pull Changes from Specific Branch
**State A:** Odoo installation with Git configured and remote changes available on a specific branch
**Actions:**
1. Make changes to a specific branch in the remote repository
2. Run `./git_panel.sh pull branch_name`

**State B:**
- Display shows "Changes pulled successfully"
- Local repository has incorporated the remote changes from the specified branch

#### Test 3.4: Push Local Changes
**State A:** Odoo installation with Git configured and local changes made
**Actions:**
1. Modify files in the addons directory
2. Run `./git_panel.sh push`
3. Enter a commit message when prompted

**State B:**
- Display shows changes to be committed with statistics
- Display shows "Changes pushed successfully"
- Remote repository has incorporated the local changes (verify on GitHub)

### 4. Branch Management Tests

#### Test 4.1: List Branches
**State A:** Odoo installation with Git configured and multiple branches
**Actions:**
1. Run `./git_panel.sh list-branches`

**State B:**
- Display shows local branches
- Display shows remote branches
- Current branch is indicated

#### Test 4.2: Branch Creation with Staging
**State A:** Odoo installation with Git configured and no staging environments
**Actions:**
1. Run `./staging.sh create staging1`

**State B:**
- Staging environment created
- Git branch "staging-staging1" created from main
- Branch information stored in `.git_branch` file in staging directory

#### Test 4.3: Branch Deletion with Staging
**State A:** Odoo installation with Git configured and a staging environment
**Actions:**
1. Run `./staging.sh delete staging1`

**State B:**
- Staging environment deleted
- Git branch "staging-staging1" deleted
- Warning displayed if there are uncommitted changes

### 5. Integration Tests

#### Test 5.1: Creating Staging Environment with Git Branch
**State A:** Odoo installation with Git configured and no staging environments
**Actions:**
1. Run `./staging.sh create staging1`

**State B:**
- Staging environment created
- Git branch "staging-staging1" created from main
- Branch information stored in `.git_branch` file in staging directory
- Staging database created with proper naming

#### Test 5.2: Deleting Staging Environment with Git Branch
**State A:** Odoo installation with Git configured and a staging environment
**Actions:**
1. Make changes in the staging branch
2. Run `./staging.sh delete staging1`

**State B:**
- Warning displayed about uncommitted changes
- Confirmation requested before deletion
- Staging environment deleted after confirmation
- Git branch "staging-staging1" deleted

#### Test 5.3: Updating Staging Environment with Git Branch
**State A:** Odoo installation with Git configured and a staging environment
**Actions:**
1. Run `./staging.sh update staging1`

**State B:**
- Staging environment updated from production
- Git branch maintained with its changes

### 6. Edge Case Tests

#### Test 6.1: Git Not Installed
**State A:** System without Git installed
**Actions:**
1. Run `./git_panel.sh setup`

**State B:**
- Error message displayed about Git not being installed
- Instructions provided on how to install Git

#### Test 6.2: Network Connectivity Issues
**State A:** Odoo installation with Git configured but no internet connection
**Actions:**
1. Disconnect from the internet
2. Run `./git_panel.sh fetch`

**State B:**
- Error message displayed about network connectivity issues
- Graceful handling of the error

#### Test 6.3: Permission Issues
**State A:** Odoo installation with Git configured but insufficient permissions
**Actions:**
1. Change permissions of the addons directory to be read-only
2. Run `./git_panel.sh push`

**State B:**
- Error message displayed about permission issues
- Graceful handling of the error

#### Test 6.4: Merge Conflicts
**State A:** Odoo installation with Git configured and potential merge conflicts
**Actions:**
1. Make changes to the same file in both local and remote repositories
2. Run `./git_panel.sh pull`

**State B:**
- Warning displayed about merge conflicts
- Instructions provided on how to resolve conflicts

## Troubleshooting Common Issues

### Authentication Failures
- Verify that the GitHub token has the correct permissions (repo scope)
- Ensure the token hasn't expired
- Check for typos in the username or token

### Repository URL Issues
- Ensure the URL is in the format: https://github.com/username/repo
- Verify that the repository exists and is accessible with your credentials

### Branch Management Issues
- Ensure that the main branch is named "main" (not "master")
- Verify that staging branch names follow the expected format

### Integration Issues
- Check that the staging.sh script is properly integrated with git_panel.sh
- Verify that the .git_branch files are created and read correctly

## Reporting Test Results

For each test, document:
1. Test ID and description
2. Initial state (State A)
3. Actions performed
4. Expected end state (State B)
5. Actual end state
6. Pass/Fail status
7. Any issues or observations

This comprehensive testing approach ensures that the Git Panel feature works reliably in all scenarios and provides a good user experience.
