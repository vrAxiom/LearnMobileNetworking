#!/bin/bash
set -euo pipefail

TOKEN="${GITHUB_TOKEN:-}"
REPO_NAME="LearnMobileNetworking"
REPO_DESCRIPTION="Interactive single-page learning hub for Mobile Network Architecture - 7 chapters, 28-question quiz, 50+ glossary terms"

if [ -z "$TOKEN" ]; then
  echo "Error: GITHUB_TOKEN is not set."
  echo "Run: export GITHUB_TOKEN=your_token"
  exit 1
fi

echo "Step 1: Resolving GitHub user..."
USER_JSON=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/user)
USERNAME=$(printf '%s' "$USER_JSON" | tr -d '\r\n' | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
if [ -z "$USERNAME" ]; then
  echo "Error: Could not determine GitHub username from token."
  echo "$USER_JSON"
  exit 1
fi
echo "Username: $USERNAME"

echo "Step 2: Ensuring repository exists..."
REPO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $TOKEN" "https://api.github.com/repos/$USERNAME/$REPO_NAME")
if [ "$REPO_STATUS" = "200" ]; then
  echo "Repo already exists: $USERNAME/$REPO_NAME"
else
  RESPONSE=$(curl -s -X POST \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/user/repos \
    -d "{\"name\": \"$REPO_NAME\", \"description\": \"$REPO_DESCRIPTION\", \"private\": false, \"auto_init\": false}")

  if echo "$RESPONSE" | grep -q '"full_name"'; then
    echo "Repo created: $USERNAME/$REPO_NAME"
  elif echo "$RESPONSE" | grep -qi 'name already exists on this account'; then
    echo "Repo already exists: $USERNAME/$REPO_NAME"
  else
    echo "Error: Failed to create repository."
    echo "$RESPONSE"
    exit 1
  fi
fi

echo "Step 3: Configuring git remote and pushing..."
PUBLIC_REMOTE_URL="https://github.com/$USERNAME/$REPO_NAME.git"
AUTH_PUSH_URL="https://$TOKEN@github.com/$USERNAME/$REPO_NAME.git"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$PUBLIC_REMOTE_URL"
else
  git remote add origin "$PUBLIC_REMOTE_URL"
fi
git remote set-url --push origin "$AUTH_PUSH_URL"

git branch -M main

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  git add -A
  git commit -m "Initial commit"
fi

# Ensure pull/rebase operations do not fail due to unstaged or untracked files.
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git add -A
  git commit -m "Update project files" || true
fi

if ! git push -u origin main; then
  echo "Push rejected. Syncing with remote main and retrying..."
  git fetch origin main

  if ! git rebase origin/main; then
    echo "Rebase failed, trying merge fallback..."
    git rebase --abort 2>/dev/null || true
    git merge --no-edit --allow-unrelated-histories origin/main
  fi

  git push -u origin main
fi

echo ""
echo "Done! Your repo: https://github.com/$USERNAME/$REPO_NAME"
echo "Enable GitHub Pages: Settings -> Pages -> Branch: main -> Save"
echo "Live URL will be: https://$USERNAME.github.io/$REPO_NAME"
