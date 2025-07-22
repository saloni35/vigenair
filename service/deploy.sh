#!/bin/bash
# Copyright 2024 Google LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

gcloud config set project abiding-operand-466609-a0
gcloud services enable cloudresourcemanager.googleapis.com
gcloud auth application-default set-quota-project abiding-operand-466609-a0
printf "\nINFO - GCP project set to 'abiding-operand-466609-a0' succesfully!\n"

BUCKET_EXISTS=$(gcloud storage ls gs://bucket-my-first-project > /dev/null 2>&1 && echo "true" || echo "false")
if "${BUCKET_EXISTS}"; then
  printf "\nWARN - Bucket 'bucket-my-first-project' already exists. Skipping bucket creation...\n"
else
  gcloud storage buckets create gs://bucket-my-first-project --project=abiding-operand-466609-a0 --location=us-central1 --uniform-bucket-level-access
  test $? -eq 0 || exit
  printf "\nINFO - Bucket 'bucket-my-first-project' created successfully in location 'us-central1'!\n"
fi

printf "\nINFO - Enabling GCP APIs...\n"
gcloud services enable \
  aiplatform.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudfunctions.googleapis.com \
  compute.googleapis.com \
  eventarc.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com \
  run.googleapis.com \
  script.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com \
  videointelligence.googleapis.com

PROJECT_NUMBER=$(gcloud projects describe abiding-operand-466609-a0 --format="value(projectNumber)")
STORAGE_SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
EVENTARC_SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com"
VERTEXAI_SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gcp-sa-aiplatform.iam.gserviceaccount.com"
COMPUTE_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
printf "\nINFO - Creating Service Agents and granting roles...\n"
for SA in "aiplatform.googleapis.com" "storage.googleapis.com" "eventarc.googleapis.com"; do
    gcloud --no-user-output-enabled beta services identity create --project=abiding-operand-466609-a0 \
        --service="${SA}"
done
COMPUTE_SA_ROLES=(
    "roles/eventarc.eventReceiver"
    "roles/run.invoker"
    "roles/cloudfunctions.invoker"
    "roles/storage.objectAdmin"
    "roles/aiplatform.user"
    "roles/logging.logWriter"
    "roles/artifactregistry.createOnPushWriter"
    "roles/cloudbuild.builds.builder"
)
for COMPUTE_SA_ROLE in "${COMPUTE_SA_ROLES[@]}"; do
    gcloud --no-user-output-enabled projects add-iam-policy-binding \
        abiding-operand-466609-a0 \
        --member="serviceAccount:${COMPUTE_SERVICE_ACCOUNT}" \
        --role="${COMPUTE_SA_ROLE}"
done
gcloud --no-user-output-enabled projects add-iam-policy-binding \
    abiding-operand-466609-a0 \
    --member="serviceAccount:${STORAGE_SERVICE_ACCOUNT}" \
    --role="roles/pubsub.publisher"
gcloud --no-user-output-enabled projects add-iam-policy-binding \
    abiding-operand-466609-a0 \
    --member="serviceAccount:${EVENTARC_SERVICE_ACCOUNT}" \
    --role="roles/eventarc.serviceAgent"
gcloud --no-user-output-enabled projects add-iam-policy-binding \
    abiding-operand-466609-a0 \
    --member="serviceAccount:${VERTEXAI_SERVICE_ACCOUNT}" \
    --role="roles/storage.objectViewer"
printf "Operation finished successfully!\n"
printf "\nINFO - Deploying the 'vigenair' Cloud Function...\n"
gcloud functions deploy vigenair \
--env-vars-file .env.yaml \
--gen2 \
--region=us-central1 \
--runtime=python310 \
--source=. \
--entry-point=gcs_file_uploaded \
--timeout=540s \
--memory=1Gi \
--cpu=1 \
--trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
--trigger-event-filters="bucket=bucket-my-first-project" \
--trigger-location="us"
test $? -eq 0 || exit
