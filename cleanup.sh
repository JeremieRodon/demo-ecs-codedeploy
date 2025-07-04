#!/bin/sh

# Simple cleanup script for ECS CodeDeploy Demo

set -e

PROJECT_NAME="ecs-codedeploy-demo"
FOUNDATIONS_STACK_NAME="${PROJECT_NAME}-foundations"
APPLICATION_STACK_NAME="${PROJECT_NAME}-application"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "🧹 Cleaning up ECS CodeDeploy Demo..."
echo "Application Stack: $APPLICATION_STACK_NAME"
echo "Foundations Stack: $FOUNDATIONS_STACK_NAME"
echo "Region: $REGION"
echo ""

# Function to cleanup task definitions
# This function delegates to the dedicated cleanup-task-definitions.sh script
# which provides comprehensive task definition cleanup with better error handling
cleanup_task_definitions() {
    echo "🗂️  Cleaning up task definitions..."

    # Get the directory of this script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Call the dedicated cleanup script with --force to skip confirmation
    # since this is part of a larger cleanup operation
    if [[ -f "$SCRIPT_DIR/scripts/cleanup-task-definitions.sh" ]]; then
        "$SCRIPT_DIR/scripts/cleanup-task-definitions.sh" \
            --family "$PROJECT_NAME" \
            --region "$REGION" \
            --force
    else
        echo "❌ Error: cleanup-task-definitions.sh script not found"
        echo "   Expected location: $SCRIPT_DIR/scripts/cleanup-task-definitions.sh"
        exit 1
    fi
}

# Clean up task definitions first (before deleting the stack)
cleanup_task_definitions

# Delete application stack first
if aws cloudformation describe-stacks --stack-name "$APPLICATION_STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "🗑️  Deleting application stack..."

    # Delete the application stack
    aws cloudformation delete-stack --stack-name "$APPLICATION_STACK_NAME" --region "$REGION"

    echo "⏳ Waiting for application stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$APPLICATION_STACK_NAME" --region "$REGION"

    echo "✅ Application stack deleted successfully!"
else
    echo "ℹ️  Application stack doesn't exist, skipping..."
fi

# Delete foundations stack second
if aws cloudformation describe-stacks --stack-name "$FOUNDATIONS_STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "🗑️  Deleting foundations stack..."

    # Empty ECR repository first
    ECR_REPO=$(aws cloudformation describe-stacks \
        --stack-name "$FOUNDATIONS_STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryName`].OutputValue' \
        --output text 2>/dev/null || echo "")

    if [[ -n "$ECR_REPO" ]]; then
        echo "📦 Emptying ECR repository..."
        IMAGE_IDS=$(aws ecr list-images --repository-name "$ECR_REPO" --region "$REGION" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
        if [[ "$IMAGE_IDS" != "[]" ]]; then
            aws ecr batch-delete-image --repository-name "$ECR_REPO" --image-ids "$IMAGE_IDS" --region "$REGION" 2>/dev/null || true
        fi
    fi

    # Delete the foundations stack
    aws cloudformation delete-stack --stack-name "$FOUNDATIONS_STACK_NAME" --region "$REGION"

    echo "⏳ Waiting for foundations stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$FOUNDATIONS_STACK_NAME" --region "$REGION"

    echo "✅ Foundations stack deleted successfully!"
else
    echo "ℹ️  Foundations stack doesn't exist, skipping..."
fi

# Final cleanup verification
echo "🔍 Verifying cleanup completion..."

# Check for any remaining CodeDeploy deployments
echo "🚀 Checking for active CodeDeploy deployments..."
ACTIVE_DEPLOYMENTS=$(aws deploy list-deployments \
    --application-name "$PROJECT_NAME" \
    --include-only-statuses "Created" "Queued" "InProgress" \
    --region "$REGION" \
    --query 'length(deployments)' \
    --output text 2>/dev/null || echo "0")

if [[ "$ACTIVE_DEPLOYMENTS" != "0" ]]; then
    echo "⚠️  Warning: $ACTIVE_DEPLOYMENTS active deployment(s) found"
    echo "    These will be cleaned up when the stack is deleted"
else
    echo "✅ No active deployments found"
fi

echo ""
echo "🎉 Cleanup completed!"
echo ""
echo "📊 Resources cleaned up:"
echo "  ✅ CloudFormation stacks deleted"
echo "  ✅ ECR repository emptied and deleted"
echo "  ✅ ECS task definitions cleaned up (see above for details)"
echo "  ✅ All demo resources removed"
echo ""
echo "💡 Note: If you encounter any issues, you can:"
echo "   - Check the AWS console for any remaining resources"
echo "   - Run this script again to retry cleanup"
echo "   - Manually delete any remaining resources if needed"
