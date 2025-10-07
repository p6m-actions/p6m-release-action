#! /bin/bash
set -euo pipefail

DRY_RUN=false
TAGS=()
COMMIT_MESSAGE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --tag)
      TAGS+=("$2")
      shift 2
      ;;
    --message)
      COMMIT_MESSAGE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

SHA=$(gh api '/repos/'$GITHUB_REPOSITORY'/branches/'$GITHUB_REF_NAME | jq -er .commit.sha)
cp $GITHUB_ACTION_PATH/createCommit.json $RUNNER_TEMP/body.json

BODY=$(cat $RUNNER_TEMP/body.json |\
    yq '.variables.input.branch.branchName = "'$GITHUB_REF_NAME'"' |\
    yq '.variables.input.branch.repositoryNameWithOwner = "'$GITHUB_REPOSITORY'"' |\
    yq '.variables.input.message.headline = "'"$COMMIT_MESSAGE"'"' |\
    yq '.variables.input.expectedHeadOid = "'$SHA'"' |\
    yq -o json -I0)
echo "$BODY" > $RUNNER_TEMP/body.json

CHANGED_FILES=$(git diff --name-only)
for file in $CHANGED_FILES; do
    # Make sure to remove the `./` at the start of the file path since Github hates that.
    export FILE_PATH="${file#./}"
    export FILE_CONTENTS=$(base64 -w0 -i "$file")
    yq -io json -I0 '.variables.input.fileChanges.additions += [{"path": env(FILE_PATH), "contents": env(FILE_CONTENTS)}]' $RUNNER_TEMP/body.json
done

if [ "$DRY_RUN" = true ]; then
  for tag in "${TAGS[@]}"; do
    echo "[DRY RUN] gh api -X POST /repos/$GITHUB_REPOSITORY/git/refs -f ref=refs/tags/$tag -f sha=$SHA"
  done

  echo "[DRY RUN] gh api graphql --input $RUNNER_TEMP/body.json"
  echo 'Create Commit Request Body:'
  yq -o json $RUNNER_TEMP/body.json
  NEW_SHA=""
else
  for tag in "${TAGS[@]}"; do
    gh api -X POST /repos/$GITHUB_REPOSITORY/git/refs -f "ref=refs/tags/$tag" -f "sha=$SHA"
  done

  # Using the gh cli produces a VERIFIED commit.
  RESPONSE=$(gh api graphql --input $RUNNER_TEMP/body.json)
  echo "$RESPONSE" | yq -o json
  NEW_SHA=$(echo "$RESPONSE" | jq -er '.data.createCommitOnBranch.commit.oid')
fi

echo "new_sha=$NEW_SHA" >> $GITHUB_OUTPUT
