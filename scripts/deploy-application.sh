#!/bin/sh

# Application Deploy Script for ECS CodeDeploy Demo

set -e

PROJECT_NAME="ecs-codedeploy-demo"
FOUNDATIONS_STACK_NAME="${PROJECT_NAME}-foundations"
APPLICATION_STACK_NAME="${PROJECT_NAME}-application"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Deploying ECS CodeDeploy Demo Application..."
echo "Application Stack: $APPLICATION_STACK_NAME"
echo "Region: $REGION"
echo ""

# Check if foundations stack exists
if ! aws cloudformation describe-stacks --stack-name "$FOUNDATIONS_STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "❌ ERROR: Foundations stack not found: $FOUNDATIONS_STACK_NAME"
    echo "Please deploy the foundations stack first:"
    echo "  ./deploy-foundations.sh"
    echo ""
    exit 1
fi

echo "✅ Foundations stack found: $FOUNDATIONS_STACK_NAME"
echo ""

# Check if application stack exists
if aws cloudformation describe-stacks --stack-name "$APPLICATION_STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "📝 Updating existing application stack..."
    aws cloudformation update-stack \
        --stack-name "$APPLICATION_STACK_NAME" \
        --template-body file://"$SCRIPT_DIR/../cloudformation/2-demo-application.yaml" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo "⏳ Waiting for application stack update to complete..."
    aws cloudformation wait stack-update-complete --stack-name "$APPLICATION_STACK_NAME" --region "$REGION"
else
    echo "🆕 Creating new application stack..."
    aws cloudformation create-stack \
        --stack-name "$APPLICATION_STACK_NAME" \
        --template-body file://"$SCRIPT_DIR/../cloudformation/2-demo-application.yaml" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo "⏳ Waiting for application stack creation to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$APPLICATION_STACK_NAME" --region "$REGION"
fi

echo ""
echo "✅ Application stack deployment completed!"
