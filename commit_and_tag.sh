#! /bin/bash
set -euo pipefail
SHA=$(gh api '/repos/'$GITHUB_REPOSITORY'/branches/'$GITHUB_REF_NAME | jq -er .commit.sha)
cp $GITHUB_ACTION_PATH/createCommit.json $RUNNER_TEMP/body.json

VERSION=$1
HELM_VERSION=${2:-}
COMMIT_MESSAGE=$3

BODY=$(cat $RUNNER_TEMP/body.json |\
    yq '.variables.input.branch.branchName = "'$GITHUB_REF_NAME'"' |\
    yq '.variables.input.branch.repositoryNameWithOwner = "'$GITHUB_REPOSITORY'"' |\
    yq '.variables.input.message.headline = "'"$COMMIT_MESSAGE"'"' |\
    yq '.variables.input.expectedHeadOid = "'$SHA'"' |\
    yq -o json -I0)
echo "$BODY" > $RUNNER_TEMP/body.json

CHANGED_FILES=$(git diff --name-only)
cat $RUNNER_TEMP/body.json
for file in $CHANGED_FILES; do
    # Make sure to remove the `./` at the start of the file path since Github hates that.
    yq -io json -I0 '.variables.input.fileChanges.additions += {"path": "'${file#./}'", "contents": "'$(base64 -w0 -i $file)'"}' $RUNNER_TEMP/body.json
done

echo 'Create Commit Request Body:'
yq -o json $RUNNER_TEMP/body.json

# Using the gh cli produces a VERIFIED commit.
RESPONSE=$(gh api graphql --input $RUNNER_TEMP/body.json)
echo "$RESPONSE" | yq -o json

NEW_SHA=$(echo "$RESPONSE" | jq -er '.data.createCommitOnBranch.commit.oid')
gh api -X POST /repos/$GITHUB_REPOSITORY/git/refs -f "ref=refs/tags/v$VERSION" -f "sha=$NEW_SHA"
if [ -n "$HELM_VERSION" ]; then
  gh api -X POST /repos/$GITHUB_REPOSITORY/git/refs -f "ref=refs/tags/helm-v$HELM_VERSION" -f "sha=$NEW_SHA"
fi
