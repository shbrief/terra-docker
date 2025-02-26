#!/bin/bash
# Run `gcloud auth configure-docker --quiet` before running this script
# Example: ./build.sh terra-jupyter-base
set -e -x

IMAGE_DIR=$1
VERSION=$(cat config/conf.json | jq -r ".image_data | .[] | select(.name == \"$IMAGE_DIR\") | .version")

TAG_NAME=$(git log --pretty=format:'%h' -n 1)
GCR_IMAGE_REPO=$(cat config/conf.json | jq -r .gcr_image_repo)

#for some reason, this command fails if the script is in strict mode because grep not finding something exits with 1
IMAGE_EXISTS=$(gcloud container images list-tags $GCR_IMAGE_REPO/$IMAGE_DIR | grep $VERSION) | true

if [ -z "$IMAGE_EXISTS" ]; then
    echo "An image for this version does not exist. Proceeding with build"
else
    echo "An image for the version you are trying to build already exists. Ensure you have updated the VERSION file."
    #unreserved exit code for checking in jenkins
    exit 14
fi

VAULT_LOCATION=~/.vault-token
if [[ $VAULT_LOCATION == *"jenkins"* ]]; then
    VAULT_LOCATION="/etc/vault-token-dsde"
fi

# will fail if you are not gcloud authed as dspci-wb-gcr-service-account
docker run --rm  -v $VAULT_LOCATION:/root/.vault-token:ro broadinstitute/dsde-toolbox:latest vault read --format=json secret/dsde/dsp-techops/common/dspci-wb-gcr-service-account.json | jq .data > dspci-wb-gcr-service-account.json
gcloud auth activate-service-account --key-file=dspci-wb-gcr-service-account.json

docker image build ./$IMAGE_DIR --tag $GCR_IMAGE_REPO/$IMAGE_DIR:$TAG_NAME --tag $GCR_IMAGE_REPO/$IMAGE_DIR:$VERSION \
    && docker push $GCR_IMAGE_REPO/$IMAGE_DIR:$TAG_NAME \
    && docker push $GCR_IMAGE_REPO/$IMAGE_DIR:$VERSION

docker run --rm -itd -u root -e PIP_USER=false --entrypoint='/bin/bash' --name $IMAGE_DIR $GCR_IMAGE_REPO/$IMAGE_DIR:$VERSION

python scripts/generate_package_docs.py "$IMAGE_DIR"

docker kill $IMAGE_DIR
docker image rm -f $GCR_IMAGE_REPO/$IMAGE_DIR:$VERSION
docker image rm -f $GCR_IMAGE_REPO/$IMAGE_DIR:$TAG_NAME

echo "Successfully completed build script for $IMAGE_DIR"
