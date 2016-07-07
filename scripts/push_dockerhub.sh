#!/bin/bash

###################################################################
### Build, tag and push semantically-versioned images to Docker Hub
###
### This script is intended to be run in a Travis-CI build context,
### where the current commit is tagged with a semantic version tag (e.g. "v3.12.7")
### The following environment variables are assumed to be set:
###
### - DOCKERHUB_EMAIL - Dockerhub login email
### - DOCKERHUB_USERNAME - Docker Hub login username
### - DOCKERHUB_PASSWORD - Docker Hub login password
###############################################################

DOCKER_IMAGE="amalgam8/a8-sidecar"

tag=$(git describe --exact-match)
if [ $? -ne 0 ]; then
    echo "Cannot push to Docker Hub because the current commit is not tagged"
    exit 1
elif [[ ! $tag =~ v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "Cannot push to Docker Hub because the current commit is not tagged in a semantic version"
    exit 1
fi

patch=$(echo $tag | sed -r 's/v([0-9]+)\.([0-9]+)\.([0-9]+)/\3/')
minor=$(echo $tag | sed -r 's/v([0-9]+)\.([0-9]+)\.([0-9]+)/\2/')
major=$(echo $tag | sed -r 's/v([0-9]+)\.([0-9]+)\.([0-9]+)/\1/')

echo "Found version tag '$tag' (MAJOR: $major, MINOR: $minor, PATCH: $patch)"

patch_tag="$major.$minor.$patch"
minor_tag="$major.$minor"
major_tag="$major"

echo "Building docker images..."
docker build -t "$DOCKER_IMAGE:latest" -f docker/Dockerfile.ubuntu .
docker build -t "$DOCKER_IMAGE:alpine" -f docker/Dockerfile.alpine .

echo "Listing current image tags in Docker Hub..."
dockerhub_tags=$(curl --silent "https://registry.hub.docker.com/v1/repositories/$DOCKER_IMAGE/tags" | jq -r ".[].name" | grep -v "alpine")

# Always push the patch version tag (e.g., '3.12.7')
push_patch=true

# Determine if the minor tag (e.g., '3.12') should be pushed
max_patch=$(echo "dockerhub_tags" | sed -rn "s/$minor_tag\.([0-9]+)/\1/p" | sort -r | head -n1)
if [[ -z "$max_patch" || $patch -ge $max_patch ]]; then
    push_minor=true
fi

# Determine if the major tag (e.g., '3') should be pushed
max_minor=$(echo "dockerhub_tags" | sed -rn "s/$major_tag\.([0-9]+)\.[0-9]+/\1/p" | sort -r | head -n1)
if [[ $major -gt 0 && $push_minor = true && ( -z "$max_minor" || $minor -ge $max_minor ) ]]; then
    push_major=true
fi

# Determine if the 'latest' tag should be pushed
max_major=$(echo "dockerhub_tags" | sed -rn "s/([0-9]+)\.[0-9]+\.[0-9]+/\1/p" | sort -r | head -n1)
if [[ ( $push_major = true || $major -eq 0 ) && $push_minor = true && ( -z "$max_major" || $major -ge $max_major ) ]]; then
    push_latest=true
fi

echo "Signing into Docker Hub..."
docker login --email $DOCKERHUB_EMAIL --username $DOCKERHUB_USERNAME --password $DOCKERHUB_PASSWORD

if [ "$push_patch" = true ]; then
    echo "Pushing '$DOCKER_IMAGE:$patch_tag' to Docker Hub..."
    docker tag "$DOCKER_IMAGE:latest" "$DOCKER_IMAGE:$patch_tag"
    docker push "$DOCKER_IMAGE:$patch_tag"
    echo "Pushing '$DOCKER_IMAGE:$patch_tag-alpine' to Docker Hub..."
    docker tag "$DOCKER_IMAGE:alpine" "$DOCKER_IMAGE:$patch_tag-alpine"
    docker push "$DOCKER_IMAGE:$patch_tag-alpine"
fi
if [ "$push_minor" = true ]; then
    echo "Pushing '$DOCKER_IMAGE:$minor_tag' to Docker Hub..."
    docker tag "$DOCKER_IMAGE:latest" "$DOCKER_IMAGE:$minor_tag"
    docker push "$DOCKER_IMAGE:$minor_tag"
    echo "Pushing '$DOCKER_IMAGE:$minor_tag-alpine' to Docker Hub..."
    docker tag "$DOCKER_IMAGE:alpine" "$DOCKER_IMAGE:$minor_tag-alpine"
    docker push "$DOCKER_IMAGE:$minor_tag-alpine"
fi
if [ "$push_major" = true ]; then
    echo "Pushing '$DOCKER_IMAGE:$major_tag' to Docker Hub..."
    docker tag "$DOCKER_IMAGE:latest" "$DOCKER_IMAGE:$major_tag"
    docker push "$DOCKER_IMAGE:$major_tag"
    echo "Pushing '$DOCKER_IMAGE:$major_tag-alpine' to Docker Hub..."
    docker tag "$DOCKER_IMAGE:alpine" "$DOCKER_IMAGE:$major_tag-alpine"
    docker push "$DOCKER_IMAGE:$major_tag-alpine"
fi
if [ "$push_latest" = true ]; then
    echo "Pushing '$DOCKER_IMAGE:latest' to Docker Hub..."
    docker push "$DOCKER_IMAGE:latest"
    echo "Pushing '$DOCKER_IMAGE:alpine' to Docker Hub..."
    docker push "$DOCKER_IMAGE:alpine"
fi

echo "Signing out of Docker Hub"
docker logout
