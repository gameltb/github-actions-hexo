#!/bin/sh
set -e

# setup key
mkdir -p /root/.ssh/
echo "${INPUT_DEPLOYKEY}" >/root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa
ssh-keyscan -t rsa github.com >>/root/.ssh/known_hosts

git config --global user.name "${INPUT_USERNAME:-GitHub Action}"
git config --global user.email "${INPUT_EMAIL:-action@github.com}"

# setup hexo env
npm install -g hexo-cli
npm install hexo-deployer-git
npm install

# create new hexo post
if [ "x"${INPUT_USE_NEW_POST_CMD} == "xtrue" ] && [ -f n ]; then
    hexo n "`head -n1 n | awk  -F '\0'  '{print $2}'`" "`head -n1 n | awk  -F '\0'  '{print $1}'`"
    rm n
    find ./source -type d -empty -print0 | xargs -0 -I {} touch "{}"/.gitignore
    git add .
    remote_repo="git@github.com:${GITHUB_REPOSITORY}.git"
    git commit -m "commit by github action new post" -a
    git push "${remote_repo}" HEAD:${INPUT_BRANCH}
    exit
fi

# generate&publish
hexo g
hexo d

# Purge cache in CloudFlare
if ${INPUT_IF_UPDATE_CLOUDFLARE}; then
    [ -z "${INPUT_CLOUDFLARE_TOKEN}" ] && {
        echo 'Missing input cloudflare api key'
        exit 1
    }
    if [ -n "${INPUT_PURGE_LIST}" ]; then
        HTTP_RESPONSE=$(curl -sS "https://api.cloudflare.com/client/v4/zones/${INPUT_CLOUDFLARE_ZONE}/purge_cache" \
            -H "Authorization: Bearer ${INPUT_CLOUDFLARE_TOKEN}" \
            -H "Content-Type: application/json" \
            -w "HTTPSTATUS:%{http_code}" \
            --data '{"files":'"${INPUT_PURGE_LIST}"'}')
    else
        HTTP_RESPONSE=$(curl -sS "https://api.cloudflare.com/client/v4/zones/${INPUT_CLOUDFLARE_ZONE}/purge_cache" \
            -H "Authorization: Bearer ${INPUT_CLOUDFLARE_TOKEN}" \
            -H "Content-Type: application/json" \
            -w "HTTPSTATUS:%{http_code}" \
            --data '{"purge_everything":true}')
    fi

    # curl-get-status-code-and-response-body
    # https://gist.github.com/maxcnunes/9f77afdc32df354883df

    HTTP_BODY=$(echo "${HTTP_RESPONSE}" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
    HTTP_STATUS=$(echo "${HTTP_RESPONSE}" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')

    # example using the status
    if [ "${HTTP_STATUS}" -eq "200" ]; then
        echo "Clear successful!"
        exit 0
    else
        echo "Something was wrong, error info:"
        echo "${HTTP_BODY}"
        exit 1
    fi
fi
