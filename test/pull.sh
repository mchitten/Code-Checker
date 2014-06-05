#!/bin/bash

# source ~/.bash_profile

COMPARE_BRANCH="$2"
COMPARE_REPO="$1"

cat > ~/.ssh/config <<DELIM
Host mchitten-test
  HostName github.com
  User git
  IdentityFile ~/Sites/Code-Checker/id_rsa_mchitten_test.pub
DELIM

mkdir -p mchitten
cd mchitten && git init --quiet

git remote add original_mchitten_test git@mchitten-test:$COMPARE_REPO

$(git fetch --quiet original_mchitten_test && git remote add compare git@mchitten-test:$COMPARE_REPO)

files=""
for i in $(git fetch --quiet compare && git diff --diff-filter=ACMR original_mchitten_test/master compare/$COMPARE_BRANCH --name-only)
do
  echo $i
  git checkout compare/$COMPARE_BRANCH -- $i
  files="$files $i"
done

rubocop --format=json $files
git remote remove compare
cd ../
# rm -rf mchitten

