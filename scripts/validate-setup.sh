#!/bin/sh

# ECS CodeDeploy Demo - Validate Setup Script
# This script validates that all components are properly deployed

set -e  # Exit on any error

# Configuration
PROJECT_NAME="ecs-codedeploy-demo"
FOUNDATIONS_STACK_NAME="${PROJECT_NAME}-foundations"
APPLICATION_STACK_NAME="${PROJECT_NAME}-application"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check stack status
check_stack_status() {
    local stack_name=$1
    local stack_description=$2

    print_status $BLUE "Checking $stack_description..."

    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" &>/dev/null; then
        local stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text)

        if [[ "$stack_status" == "CREATE_COMPLETE" || "$stack_status" == "UPDATE_COMPLETE" ]]; then
            print_status $GREEN "✓ $stack_description is deployed and healthy"
            return 0
        else
            print_status $RED "✗ $stack_description exists but status is: $stack_status"
            return 1
        fi
    else
        print_status $RED "✗ $stack_description not found"
        return 1
    fi
}

# Function to check ECR repository
check_ecr_repository() {
    print_status $BLUE "Checking ECR repository..."

    local ecr_repo_name=$(aws cloudformation describe-stacks \
        --stack-name "$FOUNDATIONS_STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryName`].OutputValue' \
        --output text 2>/dev/null || echo "")

    if [[ -n "$ecr_repo_name" ]]; then
        # Check if repository has images
        local image_count=$(aws ecr list-images \
            --repository-name "$ecr_repo_name" \
            --region "$REGION" \
            --query 'length(imageIds)' \
            --output text 2>/dev/null || echo "0")

        if [[ "$image_count" -gt 0 ]]; then
            print_status $GREEN "✓ ECR repository has $image_count image(s)"

            # List available tags
            local tags=$(aws ecr list-images \
                --repository-name "$ecr_repo_name" \
                --region "$REGION" \
                --query 'imageIds[?imageTag!=null].imageTag' \
                --output text 2>/dev/null | tr '\t' ' ')

            print_status $BLUE "  Available tags: $tags"
            return 0
        else
            print_status $YELLOW "⚠ ECR repository exists but has no images"
            print_status $BLUE "  Run: ../scripts/build-and-deploy.sh v1.0"
            return 1
        fi
    else
        print_status $RED "✗ Could not get ECR repository name"
        return 1
    fi
}

# Function to check ECS service
check_ecs_service() {
    print_status $BLUE "Checking ECS service..."

    local cluster_name="$PROJECT_NAME"
    local service_name="$PROJECT_NAME"

    local running_count=$(aws ecs describe-services \
        --cluster "$cluster_name" \
        --services "$service_name" \
        --region "$REGION" \
        --query 'services[0].runningCount' \
        --output text 2>/dev/null || echo "0")

    local desired_count=$(aws ecs describe-services \
        --cluster "$cluster_name" \
        --services "$service_name" \
        --region "$REGION" \
        --query 'services[0].desiredCount' \
        --output text 2>/dev/null || echo "0")

    if [[ "$running_count" -ge "$desired_count" && "$running_count" -gt 0 ]]; then
        print_status $GREEN "✓ ECS service is healthy ($running_count/$desired_count tasks running)"
        return 0
    else
        print_status $YELLOW "⚠ ECS service status: $running_count/$desired_count tasks running"
        return 1
    fi
}

# Function to check ALB health
check_alb_health() {
    print_status $BLUE "Checking ALB and application health..."

    local alb_url=$(aws cloudformation describe-stacks \
        --stack-name "$APPLICATION_STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ALBUrl`].OutputValue' \
        --output text 2>/dev/null || echo "")

    if [[ -n "$alb_url" ]]; then
        print_status $BLUE "  ALB URL: $alb_url"

        # Test HTTP endpoint
        local http_status=$(curl -s -o /dev/null -w "%{http_code}" "$alb_url" --connect-timeout 10 --max-time 30 || echo "000")

        if [[ "$http_status" == "200" ]]; then
            print_status $GREEN "✓ Application is responding (HTTP $http_status)"

            # Try to extract version
            local version=$(curl -s "$alb_url" --connect-timeout 10 --max-time 30 | grep -o 'v[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "unknown")
            print_status $BLUE "  Current version: $version"
            return 0
        else
            print_status $RED "✗ Application health check failed (HTTP $http_status)"
            return 1
        fi
    else
        print_status $RED "✗ Could not get ALB URL"
        return 1
    fi
}

# Function to check CodeDeploy application
check_codedeploy() {
    print_status $BLUE "Checking CodeDeploy application..."

    local app_exists=$(aws deploy get-application \
        --application-name "$PROJECT_NAME" \
        --region "$REGION" \
        --query 'application.applicationName' \
        --output text 2>/dev/null || echo "")

    if [[ "$app_exists" == "$PROJECT_NAME" ]]; then
        print_status $GREEN "✓ CodeDeploy application exists"

        # Check for recent deployments
        local deployment_count=$(aws deploy list-deployments \
            --application-name "$PROJECT_NAME" \
            --region "$REGION" \
            --query 'length(deployments)' \
            --output text 2>/dev/null || echo "0")

        print_status $BLUE "  Total deployments: $deployment_count"
        return 0
    else
        print_status $RED "✗ CodeDeploy application not found"
        return 1
    fi
}

# Function to check integration test Lambda
check_integration_test() {
    print_status $BLUE "Checking integration test Lambda function..."

    local function_name=$(aws cloudformation describe-stacks \
        --stack-name "$APPLICATION_STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`IntegrationTestFunctionName`].OutputValue' \
        --output text 2>/dev/null || echo "")

    if [[ -n "$function_name" ]]; then
        # Check if function exists and is active
        local function_state=$(aws lambda get-function \
            --function-name "$function_name" \
            --region "$REGION" \
            --query 'Configuration.State' \
            --output text 2>/dev/null || echo "")

        if [[ "$function_state" == "Active" ]]; then
            print_status $GREEN "✓ Integration test Lambda function is active"
            print_status $BLUE "  Function: $function_name"

            # Check test URL availability
            local test_url=$(aws cloudformation describe-stacks \
                --stack-name "$APPLICATION_STACK_NAME" \
                --region "$REGION" \
                --query 'Stacks[0].Outputs[?OutputKey==`TestUrl`].OutputValue' \
                --output text 2>/dev/null || echo "")

            if [[ -n "$test_url" ]]; then
                print_status $BLUE "  Test URL: $test_url"
                return 0
            else
                print_status $YELLOW "⚠ Test URL not found in stack outputs"
                return 1
            fi
        else
            print_status $RED "✗ Integration test Lambda function state: $function_state"
            return 1
        fi
    else
        print_status $RED "✗ Integration test Lambda function not found"
        return 1
    fi
}

# Function to show next steps
show_next_steps() {
    local foundations_ok=$1
    local application_ok=$2
    local ecr_has_images=$3
    local app_healthy=$4

    echo ""
    print_status $YELLOW "=== NEXT STEPS ==="

    if [[ "$foundations_ok" -ne 0 ]]; then
        print_status $BLUE "1. Deploy foundations stack:"
        print_status $BLUE "   ./scripts/deploy-foundations.sh"
    elif [[ "$ecr_has_images" -ne 0 ]]; then
        print_status $BLUE "1. Build and push initial image:"
        print_status $BLUE "   ./scripts/build-and-deploy.sh v1.0"
    elif [[ "$application_ok" -ne 0 ]]; then
        print_status $BLUE "1. Deploy application infrastructure:"
        print_status $BLUE "   ./scripts/deploy-application.sh"
    elif [[ "$app_healthy" -ne 0 ]]; then
        print_status $BLUE "1. Wait for ECS tasks to become healthy (2-3 minutes)"
        print_status $BLUE "2. Check application: ./scripts/get-alb-url.sh --health"
    else
        print_status $GREEN "🎉 Everything looks good! Try deploying a new version:"
        print_status $BLUE "   ./scripts/build-and-deploy.sh v2.0"
        print_status $BLUE ""
        print_status $BLUE "Test integration testing with failure demo:"
        print_status $BLUE "   ./scripts/build-and-deploy.sh v4.0  # Should fail and rollback"
        print_status $BLUE ""
        print_status $BLUE "Or access your application:"
        print_status $BLUE "   ./scripts/get-alb-url.sh --open"
        print_status $BLUE ""
        print_status $BLUE "When done, clean up all resources:"
        print_status $BLUE "   ./cleanup.sh"
    fi
}

# Main validation function
main() {
    print_status $BLUE "=== ECS CodeDeploy Demo - Setup Validation ==="
    print_status $BLUE "Region: $REGION"
    print_status $BLUE "Project: $PROJECT_NAME"
    echo ""

    local foundations_ok=0
    local application_ok=0
    local ecr_has_images=0
    local ecs_ok=0
    local alb_ok=0
    local codedeploy_ok=0
    local integration_test_ok=0

    # Check stacks
    check_stack_status "$FOUNDATIONS_STACK_NAME" "Foundations Stack" || foundations_ok=1
    check_stack_status "$APPLICATION_STACK_NAME" "Application Stack" || application_ok=1

    echo ""

    # Check ECR repository and images
    if [[ "$foundations_ok" -eq 0 ]]; then
        check_ecr_repository || ecr_has_images=1
    fi

    # Check services if application stack is deployed
    if [[ "$application_ok" -eq 0 ]]; then
        echo ""
        check_ecs_service || ecs_ok=1
        check_alb_health || alb_ok=1
        check_codedeploy || codedeploy_ok=1
        check_integration_test || integration_test_ok=1
    fi

    # Summary
    echo ""
    print_status $YELLOW "=== VALIDATION SUMMARY ==="

    local total_checks=0
    local passed_checks=0

    # Foundations Stack
    total_checks=$((total_checks + 1))
    if [[ "$foundations_ok" -eq 0 ]]; then
        passed_checks=$((passed_checks + 1))
        print_status $GREEN "✓ Foundations Stack"
    else
        print_status $RED "✗ Foundations Stack"
    fi

    # ECR Images
    if [[ "$foundations_ok" -eq 0 ]]; then
        total_checks=$((total_checks + 1))
        if [[ "$ecr_has_images" -eq 0 ]]; then
            passed_checks=$((passed_checks + 1))
            print_status $GREEN "✓ ECR Images"
        else
            print_status $RED "✗ ECR Images"
        fi
    fi

    # Application Stack
    total_checks=$((total_checks + 1))
    if [[ "$application_ok" -eq 0 ]]; then
        passed_checks=$((passed_checks + 1))
        print_status $GREEN "✓ Application Stack"
    else
        print_status $RED "✗ Application Stack"
    fi

    # Services (only if application stack exists)
    if [[ "$application_ok" -eq 0 ]]; then
        total_checks=$((total_checks + 4))

        if [[ "$ecs_ok" -eq 0 ]]; then
            passed_checks=$((passed_checks + 1))
            print_status $GREEN "✓ ECS Service"
        else
            print_status $RED "✗ ECS Service"
        fi

        if [[ "$alb_ok" -eq 0 ]]; then
            passed_checks=$((passed_checks + 1))
            print_status $GREEN "✓ Application Health"
        else
            print_status $RED "✗ Application Health"
        fi

        if [[ "$codedeploy_ok" -eq 0 ]]; then
            passed_checks=$((passed_checks + 1))
            print_status $GREEN "✓ CodeDeploy"
        else
            print_status $RED "✗ CodeDeploy"
        fi

        if [[ "$integration_test_ok" -eq 0 ]]; then
            passed_checks=$((passed_checks + 1))
            print_status $GREEN "✓ Integration Test"
        else
            print_status $RED "✗ Integration Test"
        fi
    fi

    print_status $BLUE "Overall: $passed_checks/$total_checks checks passed"

    # Show cleanup info if everything is working
    if [[ "$passed_checks" -eq "$total_checks" ]]; then
        echo ""
        print_status $BLUE "💡 Cleanup Resources:"
        print_status $BLUE "   Complete cleanup: ./cleanup.sh"
        print_status $BLUE "   Task definitions only: ./scripts/cleanup-task-definitions.sh"
    fi

    # Show next steps
    show_next_steps "$foundations_ok" "$application_ok" "$ecr_has_images" "$alb_ok"

    # Exit with appropriate code
    if [[ "$passed_checks" -eq "$total_checks" ]]; then
        echo ""
        print_status $GREEN "🎉 All validations passed!"
        exit 0
    else
        echo ""
        print_status $YELLOW "⚠ Some validations failed. See next steps above."
        exit 1
    fi
}

# Run main function
main "$@"
