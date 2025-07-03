#!/bin/sh

# Simple deploy script for ECS CodeDeploy Demo

set -e

PROJECT_NAME="ecs-codedeploy-demo"
STACK_NAME="$PROJECT_NAME"
ECR_STACK_NAME="${PROJECT_NAME}-ecr"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "🚀 Deploying ECS CodeDeploy Demo..."
echo "Stack: $STACK_NAME"
echo "ECR Stack: $ECR_STACK_NAME"
echo "Region: $REGION"
echo ""

# Check if ECR stack exists
if ! aws cloudformation describe-stacks --stack-name "$ECR_STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "❌ ERROR: ECR stack not found: $ECR_STACK_NAME"
    echo "Please deploy the ECR stack first:"
    echo "  ./deploy-ecr.sh"
    echo ""
    exit 1
fi

echo "✅ ECR stack found: $ECR_STACK_NAME"
echo ""

# Check if stack exists
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "📝 Updating existing stack..."
    aws cloudformation update-stack \
        --stack-name "$STACK_NAME" \
        --template-body file://demo-stack.yaml \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo "⏳ Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"
else
    echo "🆕 Creating new stack..."
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body file://demo-stack.yaml \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo "⏳ Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
fi

echo ""
echo "✅ Stack deployment completed!"
echo ""

# Get outputs
ALB_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBUrl`].OutputValue' \
    --output text)

ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name "$ECR_STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
    --output text)

echo "🌐 Application URL: $ALB_URL"
echo "📦 ECR Repository: $ECR_URI"
echo ""
echo "Next steps:"
echo "1. Build and push your first image:"
echo "   ../scripts/build-and-deploy.sh v1.0"
echo ""
echo "2. Update to a new version to see CodeDeploy in action:"
echo "   ../scripts/build-and-deploy.sh v2.0"
