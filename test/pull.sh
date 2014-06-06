#!/bin/bash

# source ~/.bash_profile

COMPARE_REPO="$1"
COMPARE_BRANCH="$2"
UZER="$3"
REPO="$4"
RUNNING_BRANCH="$UZER/$REPO/${COMPARE_BRANCH}"
REPO_PATH="$UZER/$REPO"
GH_HOST="$UZER-$REPO"
RSA_FILE="id_rsa_${UZER}_${REPO}"
CONFIG_PATH="$PWD/test"
RSA_PATH="$CONFIG_PATH/$REPO_PATH/$RSA_FILE"

# if [[ ! -f $RSA_PATH ]]; then
#   ssh-keygen -f $RSA_PATH -N "" -q
#   cat >> ~/.ssh/config <<DELIM
# Host $GH_HOST
#   HostName github.com
#   User git
#   IdentityFile $RSA_PATH.pub
# DELIM
# fi

cd test

mkdir -p $RUNNING_BRANCH

cd $RUNNING_BRANCH && git init --quiet

if [[ ! $(git remote | grep original_${UZER}_${COMPARE_BRANCH}) ]] ; then
  git remote add original_${UZER}_${COMPARE_BRANCH} git@${GH_HOST}:${COMPARE_REPO}
fi

$(git fetch --quiet original_${UZER}_${COMPARE_BRANCH} && git remote add compare git@${GH_HOST}:${COMPARE_REPO})

files=""
for i in $(git fetch --quiet compare && git diff --diff-filter=ACMR original_${UZER}_${COMPARE_BRANCH}/master compare/${COMPARE_BRANCH} --name-only)
do
  git checkout compare/${COMPARE_BRANCH} -- $i
  files="$files $i"
done

rubocop --format json -c "${CONFIG_PATH}/rubocop.yml" --force-exclusion $files
git remote remove compare
cd ../
rm -rf $COMPARE_BRANCH

