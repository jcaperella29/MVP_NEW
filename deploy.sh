#!/usr/bin/env bash
set -euo pipefail

# Load .env if present
if [ -f .env ]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | xargs -I {} echo {})
fi

# ---- Required vars ----
: "${AWS_DEFAULT_REGION:?Set AWS_DEFAULT_REGION in .env}"
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID in .env}"
: "${ECR_REPO:=portal}"
: "${APP_RUNNER_SERVICE:=portal-service}"

IMAGE_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$ECR_REPO:latest"

echo "Region: $AWS_DEFAULT_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo "Repo: $ECR_REPO"
echo "Service: $APP_RUNNER_SERVICE"
echo "Image: $IMAGE_URI"

echo "==> Creating ECR repo (if not exists)"
aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_DEFAULT_REGION" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_DEFAULT_REGION" >/dev/null

echo "==> Logging in to ECR"
aws ecr get-login-password --region "$AWS_DEFAULT_REGION" \
| docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"

echo "==> Building image"
docker build -t "$ECR_REPO:latest" .

echo "==> Tagging image"
docker tag "$ECR_REPO:latest" "$IMAGE_URI"

echo "==> Pushing image"
docker push "$IMAGE_URI"

# Build the env JSON block from app-runner-env.json or inline minimal defaults
ENV_JSON=$(cat app-runner-env.json 2>/dev/null || echo '{"RuntimeEnvironmentVariables":[
  {"name":"FLASK_ENV","value":"production"},
  {"name":"SECRET_KEY","value":"R1pdwaIXVARB0Nbz46ccWcBwAF/nk4ZsSmaa33/B"},
  {"name":"MAIL_SERVER","value":"email-smtp.us-east-2.amazonaws.com"},
  {"name":"MAIL_PORT","value":"587"},
  {"name":"MAIL_USE_TLS","value":"true"},
  {"name":"MAIL_USERNAME","value":"YOUR_SES_SMTP_USERNAME"},
  {"name":"MAIL_PASSWORD","value":"YOUR_SES_SMTP_PASSWORD"},
  {"name":"MAIL_DEFAULT_SENDER","value":"Portal <no-reply@theinflectionpoint.com>"},
  {"name":"PUMBLE_CHANNEL_URL","value":"https://app.pumble.com/workspace/68ee4d3e2ae9236276002833/68ee4d3e2ae923627600283a"},
  {"name":"UPLOAD_ROOT","value":"/app/uploads"}
]}' )

echo "==> Creating/Updating App Runner service"
SERVICE_ARN=$(aws apprunner list-services --region "$AWS_DEFAULT_REGION" \
  --query "ServiceSummaryList[?ServiceName=='$APP_RUNNER_SERVICE'].ServiceArn" --output text)

if [ -z "$SERVICE_ARN" ] || [ "$SERVICE_ARN" == "None" ]; then
  echo "==> Creating service: $APP_RUNNER_SERVICE"
  aws apprunner create-service \
    --service-name "$APP_RUNNER_SERVICE" \
    --source-configuration "ImageRepository={
      imageIdentifier='$IMAGE_URI',
      imageRepositoryType='ECR',
      imageConfiguration={
        port='8080',
        $(echo "$ENV_JSON" | jq -r 'to_entries | .[] | "\(.key)=\(.value|tojson)"' | paste -sd, -)
      }
    }" \
    --instance-configuration Cpu=1024,Memory=2048 \
    --region "$AWS_DEFAULT_REGION" >/dev/null
else
  echo "==> Updating service: $APP_RUNNER_SERVICE"
  aws apprunner update-service \
    --service-arn "$SERVICE_ARN" \
    --source-configuration "ImageRepository={
      imageIdentifier='$IMAGE_URI',
      imageRepositoryType='ECR',
      imageConfiguration={
        port='8080',
        $(echo "$ENV_JSON" | jq -r 'to_entries | .[] | "\(.key)=\(.value|tojson)"' | paste -sd, -)
      }
    }" \
    --region "$AWS_DEFAULT_REGION" >/dev/null
fi

echo "==> Done. App Runner will provision and give you an HTTPS URL in a minute or two."
