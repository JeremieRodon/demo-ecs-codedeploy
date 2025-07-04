#!/bin/sh

# Foundations Deploy Script for ECS CodeDeploy Demo

set -e

PROJECT_NAME="ecs-codedeploy-demo"
FOUNDATIONS_STACK_NAME="${PROJECT_NAME}-foundations"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Deploying foundations for ECS CodeDeploy Demo..."
echo "Stack: $FOUNDATIONS_STACK_NAME"
echo "Region: $REGION"
echo ""

# Check if stack exists
if aws cloudformation describe-stacks --stack-name "$FOUNDATIONS_STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "📝 Updating existing foundations stack..."
    aws cloudformation update-stack \
        --stack-name "$FOUNDATIONS_STACK_NAME" \
        --template-body file://"$SCRIPT_DIR/../cloudformation/1-demo-fundations.yaml" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo "⏳ Waiting for foundations stack update to complete..."
    aws cloudformation wait stack-update-complete --stack-name "$FOUNDATIONS_STACK_NAME" --region "$REGION"
else
    echo "🆕 Creating new foundations stack..."
    aws cloudformation create-stack \
        --stack-name "$FOUNDATIONS_STACK_NAME" \
        --template-body file://"$SCRIPT_DIR/../cloudformation/1-demo-fundations.yaml" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    echo "⏳ Waiting for foundations stack creation to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$FOUNDATIONS_STACK_NAME" --region "$REGION"
fi

echo ""
echo "✅ Foundations stack deployment completed!"
echo ""

# Get outputs
ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name "$FOUNDATIONS_STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
    --output text)

echo "📦 ECR Repository: $ECR_URI"
echo "🌐 VPC and networking infrastructure deployed"
echo "🏗️ ECS cluster created"
