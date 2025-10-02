#! /bin/bash
set -euo pipefail
SHA=$(gh api '/repos/'$GITHUB_REPOSITORY'/branches/'$GITHUB_REF_NAME | jq -er .commit.sha)
cp $GITHUB_ACTION_PATH/createCommit.json $RUNNER_TEMP/body.json

BODY=$(cat $RUNNER_TEMP/body.json |\
    yq '.variables.input.branch.branchName = "'$GITHUB_REF_NAME'"' |\
    yq '.variables.input.branch.repositoryNameWithOwner = "'$GITHUB_REPOSITORY'"' |\
    yq '.variables.input.message.headline = "chore: Sync Helm Chart appVersion."' |\
    yq '.variables.input.expectedHeadOid = "'$SHA'"' |\
    yq -o json -I0)
echo "$BODY" > $RUNNER_TEMP/body.json

CHANGED_FILES=$(cat) # Read space-separated paths of files.
cat $RUNNER_TEMP/body.json
for file in $CHANGED_FILES; do
    yq -io json -I0 '.variables.input.fileChanges.additions += {"path": "'$file'", "contents": "'$(base64 -w0 -i $file)'"}' $RUNNER_TEMP/body.json
done

echo 'Create Commit Request Body:'
yq -o json $RUNNER_TEMP/body.json

# Using the gh cli produces a VERIFIED commit.
RESPONSE=$(gh api graphql --input body.json)
echo "$RESPONSE" | yq -o json

# TODO: Use response to create tag and reference for the returned oid.
