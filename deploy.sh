#!/bin/sh

# Complete Deploy Script for ECS CodeDeploy Demo
# This script orchestrates the 3 sequential steps for deployment

set -e

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

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help, -h          Show this help message"
    echo "  --region REGION     Override AWS region (default: $REGION)"
    echo "  --foundations-only  Only deploy foundations stack"
    echo "  --application-only  Only deploy application stack"
    echo ""
    echo "Examples:"
    echo "  $0                     # Deploy everything (foundations + image + application)"
    echo "  $0 --foundations-only  # Only deploy foundations"
    echo "  $0 --application-only  # Only deploy application (requires foundations)"
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    if ! command -v aws &> /dev/null; then
        print_status $RED "ERROR: AWS CLI is not installed"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        print_status $RED "ERROR: AWS CLI is not configured or credentials are invalid"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        print_status $RED "ERROR: Docker is not installed (required for building images)"
        exit 1
    fi
}

# Function to check if ECR needs v1.0 image
check_ecr_needs_image() {
    # Check if foundations stack exists
    if ! aws cloudformation describe-stacks --stack-name "$FOUNDATIONS_STACK_NAME" --region "$REGION" &>/dev/null; then
        return 1  # Foundations stack doesn't exist, can't check ECR
    fi

    # Get ECR repository name
    ECR_REPO_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$FOUNDATIONS_STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryName`].OutputValue' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$ECR_REPO_NAME" ]]; then
        return 1  # Can't get ECR repo name
    fi

    # Check if repository has images
    IMAGE_COUNT=$(aws ecr list-images \
        --repository-name "$ECR_REPO_NAME" \
        --region "$REGION" \
        --query 'length(imageIds)' \
        --output text 2>/dev/null || echo "0")

    if [[ "$IMAGE_COUNT" -eq 0 ]]; then
        return 0  # ECR is empty, needs image
    else
        return 1  # ECR has images, no need to build
    fi
}

# Main function
main() {
    print_status $BLUE "🚀 ECS CodeDeploy Demo - Complete Deployment"
    print_status $BLUE "Region: $REGION"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Step 1: Deploy foundations (if needed)
    if [[ "$APPLICATION_ONLY" != "true" ]]; then
        print_status $YELLOW "=== STEP 1: Deploying Foundations Stack ==="
        ./scripts/deploy-foundations.sh
        print_status $GREEN "✅ Foundations deployment completed"
        echo ""
    fi

    # Step 2: Build/push ECR image v1.0 (if needed)
    if [[ "$FOUNDATIONS_ONLY" != "true" ]]; then
        if check_ecr_needs_image; then
            print_status $YELLOW "=== STEP 2: Building and Pushing v1.0 Image ==="
            print_status $BLUE "ECR repository is empty, building v1.0..."
            ./scripts/build-and-deploy.sh v1.0
            print_status $GREEN "✅ v1.0 image built and pushed successfully"
            echo ""
        else
            print_status $YELLOW "=== STEP 2: ECR Image Check ==="
            print_status $GREEN "✅ ECR repository already has images, skipping build"
            echo ""
        fi
    fi

    # Step 3: Deploy application (if needed)
    if [[ "$FOUNDATIONS_ONLY" != "true" ]]; then
        print_status $YELLOW "=== STEP 3: Deploying Application Stack ==="
        ./scripts/deploy-application.sh
        print_status $GREEN "✅ Application deployment completed"
        echo ""
    fi

    # Show final summary
    print_status $GREEN "🎉 Deployment completed successfully!"
    echo ""

    # Get outputs for summary
    if aws cloudformation describe-stacks --stack-name "$FOUNDATIONS_STACK_NAME" --region "$REGION" &>/dev/null; then
        ECR_URI=$(aws cloudformation describe-stacks \
            --stack-name "$FOUNDATIONS_STACK_NAME" \
            --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
            --output text 2>/dev/null || echo "")

        if [[ -n "$ECR_URI" ]]; then
            print_status $GREEN "📦 ECR Repository: $ECR_URI"
        fi
    fi

    if aws cloudformation describe-stacks --stack-name "$APPLICATION_STACK_NAME" --region "$REGION" &>/dev/null; then
        ALB_URL=$(aws cloudformation describe-stacks \
            --stack-name "$APPLICATION_STACK_NAME" \
            --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`ALBUrl`].OutputValue' \
            --output text 2>/dev/null || echo "")

        if [[ -n "$ALB_URL" ]]; then
            print_status $GREEN "🌐 Application URL: $ALB_URL"
        fi
    fi

    echo ""
    print_status $YELLOW "=== Next Steps ==="
    print_status $BLUE "• Test automatic deployments:"
    print_status $BLUE "  ./scripts/build-and-deploy.sh v2.0"
    print_status $BLUE "• Test integration testing with failure demo:"
    print_status $BLUE "  ./scripts/build-and-deploy.sh v4.0  # Should fail and rollback"
    print_status $BLUE "• Or access your application:"
    print_status $BLUE "  ./scripts/get-alb-url.sh --open"
    print_status $BLUE "• Clean up resources:"
    print_status $BLUE "  ./cleanup.sh"
}

# Parse command line arguments
FOUNDATIONS_ONLY=false
APPLICATION_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_usage
            exit 0
            ;;
        --region)
            if [[ -z "${2:-}" ]]; then
                print_status $RED "ERROR: --region requires a value"
                exit 1
            fi
            REGION="$2"
            shift 2
            ;;
        --foundations-only)
            FOUNDATIONS_ONLY=true
            shift
            ;;
        --application-only)
            APPLICATION_ONLY=true
            shift
            ;;
        -*)
            print_status $RED "ERROR: Unknown option $1"
            show_usage
            exit 1
            ;;
        *)
            print_status $RED "ERROR: Unexpected argument $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate options
if [[ "$FOUNDATIONS_ONLY" == "true" && "$APPLICATION_ONLY" == "true" ]]; then
    print_status $RED "ERROR: Cannot specify both --foundations-only and --application-only"
    exit 1
fi

# Run main function
main
