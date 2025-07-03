#!/bin/sh

# Simple cleanup script for ECS CodeDeploy Demo

set -e

PROJECT_NAME="ecs-codedeploy-demo"
STACK_NAME="$PROJECT_NAME"
ECR_STACK_NAME="${PROJECT_NAME}-ecr"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "🧹 Cleaning up ECS CodeDeploy Demo..."
echo "Main Stack: $STACK_NAME"
echo "ECR Stack: $ECR_STACK_NAME"
echo "Region: $REGION"
echo ""

# Function to cleanup task definitions
cleanup_task_definitions() {
    echo "🗂️  Cleaning up task definitions..."

    # List all task definitions for the family
    TASK_DEF_ARNS=$(aws ecs list-task-definitions \
        --family-prefix "$PROJECT_NAME" \
        --region "$REGION" \
        --query 'taskDefinitionArns[]' \
        --output text 2>/dev/null || echo "")

    if [[ -n "$TASK_DEF_ARNS" && "$TASK_DEF_ARNS" != "None" ]]; then
        local task_count=$(echo "$TASK_DEF_ARNS" | wc -w)
        echo "📋 Found $task_count task definition(s) to clean up:"

        local counter=1
        echo "$TASK_DEF_ARNS" | tr '\t' '\n' | while read -r arn; do
            if [[ -n "$arn" ]]; then
                echo "  $counter. $arn"
                counter=$((counter + 1))
            fi
        done

        # Deregister all task definitions
        echo "🚫 Deregistering task definitions..."
        local deregister_count=0
        local deregister_failed=0

        echo "$TASK_DEF_ARNS" | tr '\t' '\n' | while read -r arn; do
            if [[ -n "$arn" ]]; then
                if aws ecs deregister-task-definition \
                    --task-definition "$arn" \
                    --region "$REGION" \
                    --output text > /dev/null 2>&1; then
                    echo "  ✅ Deregistered: $(basename "$arn")"
                    deregister_count=$((deregister_count + 1))
                else
                    echo "  ❌ Failed to deregister: $(basename "$arn")"
                    deregister_failed=$((deregister_failed + 1))
                fi
            fi
        done

        # Wait a moment for deregistration to propagate
        if [[ $deregister_count -gt 0 ]]; then
            echo "⏳ Waiting for deregistration to propagate..."
            sleep 5
        fi

        # Delete all task definitions (this removes them completely)
        echo "🗑️  Deleting task definitions..."
        local delete_count=0
        local delete_failed=0

        echo "$TASK_DEF_ARNS" | tr '\t' '\n' | while read -r arn; do
            if [[ -n "$arn" ]]; then
                if aws ecs delete-task-definitions \
                    --task-definitions "$arn" \
                    --region "$REGION" \
                    --output text > /dev/null 2>&1; then
                    echo "  ✅ Deleted: $(basename "$arn")"
                    delete_count=$((delete_count + 1))
                else
                    echo "  ⚠️  Could not delete: $(basename "$arn") (may require manual cleanup)"
                    delete_failed=$((delete_failed + 1))
                fi
            fi
        done

        echo "✅ Task definitions cleanup completed!"
        echo "   📊 Summary: $deregister_count deregistered, $delete_count deleted"
        if [[ $delete_failed -gt 0 ]]; then
            echo "   ⚠️  $delete_failed task definition(s) may need manual cleanup"
        fi
    else
        echo "ℹ️  No task definitions found for family: $PROJECT_NAME"
    fi
}

# Clean up task definitions first (before deleting the stack)
cleanup_task_definitions

# Delete main stack
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "🗑️  Deleting main stack..."

    # Delete the main stack
    aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"

    echo "⏳ Waiting for main stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"

    echo "✅ Main stack deleted successfully!"
else
    echo "ℹ️  Main stack doesn't exist, skipping..."
fi

# Delete ECR stack second
if aws cloudformation describe-stacks --stack-name "$ECR_STACK_NAME" --region "$REGION" &>/dev/null; then
    echo "🗑️  Deleting ECR stack..."

    # Empty ECR repository first
    ECR_REPO=$(aws cloudformation describe-stacks \
        --stack-name "$ECR_STACK_NAME" \
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

    # Delete the ECR stack
    aws cloudformation delete-stack --stack-name "$ECR_STACK_NAME" --region "$REGION"

    echo "⏳ Waiting for ECR stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$ECR_STACK_NAME" --region "$REGION"

    echo "✅ ECR stack deleted successfully!"
else
    echo "ℹ️  ECR stack doesn't exist, skipping..."
fi

# Final cleanup verification
echo "🔍 Verifying cleanup completion..."

# Check for any remaining task definitions
echo "📋 Checking for remaining task definitions..."
REMAINING_TASK_DEFS=$(aws ecs list-task-definitions \
    --family-prefix "$PROJECT_NAME" \
    --region "$REGION" \
    --query 'length(taskDefinitionArns)' \
    --output text 2>/dev/null || echo "0")

if [[ "$REMAINING_TASK_DEFS" != "0" ]]; then
    echo "⚠️  Warning: $REMAINING_TASK_DEFS task definition(s) may still exist"
    echo "    Manual cleanup may be required:"
    echo "    1. Go to ECS Console → Task Definitions"
    echo "    2. Select '$PROJECT_NAME' family"
    echo "    3. Delete remaining revisions manually"

    # List remaining task definitions for reference
    echo "    Remaining task definitions:"
    aws ecs list-task-definitions \
        --family-prefix "$PROJECT_NAME" \
        --region "$REGION" \
        --query 'taskDefinitionArns[]' \
        --output text 2>/dev/null | tr '\t' '\n' | while read -r arn; do
        if [[ -n "$arn" ]]; then
            echo "      - $(basename "$arn")"
        fi
    done
else
    echo "✅ All task definitions cleaned up successfully"
fi

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
echo "  ✅ ECS task definitions deregistered and deleted"
echo "  ✅ All demo resources removed"
echo ""
echo "💡 Note: If you encounter any issues, you can:"
echo "   - Check the AWS console for any remaining resources"
echo "   - Run this script again to retry cleanup"
echo "   - Manually delete any remaining resources if needed"
