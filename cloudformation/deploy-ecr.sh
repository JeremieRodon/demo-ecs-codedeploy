#!/bin/sh

# ECR Repository Deploy Script for ECS CodeDeploy Demo

set -e

PROJECT_NAME="ecs-codedeploy-demo"
ECR_STACK_NAME="${PROJECT_NAME}-ecr"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "🚀 Deploying ECR Repository for ECS CodeDeploy Demo..."
echo "Stack: $ECR_STACK_NAME"
echo "Region: $REGION"
echo ""

# Check if stack exists
if aws cloudformation describe-stacks --stack-name "$ECR_STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "📝 Updating existing ECR stack..."
    aws cloudformation update-stack \
        --stack-name "$ECR_STACK_NAME" \
        --template-body file://ecr-stack.yaml \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo "⏳ Waiting for ECR stack update to complete..."
    aws cloudformation wait stack-update-complete --stack-name "$ECR_STACK_NAME" --region "$REGION"
else
    echo "🆕 Creating new ECR stack..."
    aws cloudformation create-stack \
        --stack-name "$ECR_STACK_NAME" \
        --template-body file://ecr-stack.yaml \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo "⏳ Waiting for ECR stack creation to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$ECR_STACK_NAME" --region "$REGION"
fi

echo ""
echo "✅ ECR stack deployment completed!"
echo ""

# Get outputs
ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name "$ECR_STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
    --output text)

echo "📦 ECR Repository: $ECR_URI"
echo ""
echo "Next steps:"
echo "1. Build and push your first image:"
echo "   ../scripts/build-and-deploy.sh v1.0"
echo ""
echo "2. Deploy the main demo stack:"
echo "   ./deploy.sh"
