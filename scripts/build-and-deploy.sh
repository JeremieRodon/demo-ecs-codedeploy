#!/bin/sh

# ECS CodeDeploy Demo - Build and Deploy Script
# This script builds a specific version of the application and triggers deployment

set -e  # Exit on any error

# Configuration
PROJECT_NAME="ecs-codedeploy-demo"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLICATION_DIR="$(dirname "$SCRIPT_DIR")/application"

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
    echo "Usage: $0 <version> [options]"
    echo ""
    echo "Arguments:"
    echo "  version              Version to build and deploy (e.g., v1.0, v2.0, v3.0, v4.0)"
    echo ""
    echo "Options:"
    echo "  --help, -h          Show this help message"
    echo "  --build-only        Only build the image, don't trigger deployment"
    echo "  --local-test        Build and test locally without pushing to ECR"
    echo "  --region REGION     Override AWS region (default: $REGION)"
    echo "  --no-cache          Build without using Docker cache"
    echo ""
    echo "Examples:"
    echo "  $0 v1.0                    # Build and deploy v1.0"
    echo "  $0 v2.0 --build-only       # Only build v2.0 image"
    echo "  $0 v3.0 --local-test       # Build and test v3.0 locally"
    echo "  $0 v4.0                    # Deploy v4.0 (will fail integration tests and rollback)"
    echo ""
    echo "Available versions:"
    if [[ -d "$APPLICATION_DIR" ]]; then
        ls -1 "$APPLICATION_DIR" | grep -E '^v[0-9]+\.[0-9]+$' | sort -V || echo "  No versions found"
    else
        echo "  Application directory not found"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status $YELLOW "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_status $RED "ERROR: AWS CLI is not installed"
        exit 1
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_status $RED "ERROR: Docker is not installed"
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_status $RED "ERROR: jq is not installed"
        exit 1
    fi

    # Check AWS credentials (unless local test)
    if [[ "$LOCAL_TEST" != "true" ]]; then
        if ! aws sts get-caller-identity &> /dev/null; then
            print_status $RED "ERROR: AWS CLI is not configured or credentials are invalid"
            exit 1
        fi
    fi

    print_status $GREEN "✓ Prerequisites check passed"
}

# Function to get stack outputs
get_stack_output() {
    local stack_name=$1
    local output_key=$2

    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# Function to get AWS account ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

# Function to build Docker image
build_image() {
    local version=$1
    local version_dir="$APPLICATION_DIR/$version"

    if [[ ! -d "$version_dir" ]]; then
        print_status $RED "ERROR: Version directory not found: $version_dir"
        exit 1
    fi

    if [[ ! -f "$version_dir/Dockerfile" ]]; then
        print_status $RED "ERROR: Dockerfile not found in: $version_dir"
        exit 1
    fi

    print_status $BLUE "Building Docker image for version: $version"
    print_status $BLUE "Build directory: $version_dir"

    # Build Docker image
    local build_args=""
    if [[ "$NO_CACHE" == "true" ]]; then
        build_args="--no-cache"
    fi

    cd "$version_dir"
    docker build $build_args -t "${PROJECT_NAME}:${version}" .
    docker tag "${PROJECT_NAME}:${version}" "${PROJECT_NAME}:latest"

    print_status $GREEN "✓ Docker image built successfully"
}

# Function to test image locally
test_image_locally() {
    local version=$1

    print_status $BLUE "Testing image locally..."

    # Stop any existing container
    docker stop "${PROJECT_NAME}-test" 2>/dev/null || true
    docker rm "${PROJECT_NAME}-test" 2>/dev/null || true

    # Run container
    docker run -d --name "${PROJECT_NAME}-test" -p 8080:80 "${PROJECT_NAME}:${version}"

    # Wait for container to start
    sleep 5

    # Test HTTP endpoint
    if curl -s http://localhost:8080 > /dev/null; then
        print_status $GREEN "✓ Local test passed - container is responding"
        print_status $BLUE "View the application at: http://localhost:8080"
        echo ""
        print_status $YELLOW "Press Enter to continue (this will stop the test container)..."
        read
    else
        print_status $RED "ERROR: Local test failed - container not responding"
        docker logs "${PROJECT_NAME}-test"
        exit 1
    fi

    # Cleanup
    docker stop "${PROJECT_NAME}-test"
    docker rm "${PROJECT_NAME}-test"
    print_status $GREEN "✓ Test container cleaned up"
}

# Function to push image to ECR
push_to_ecr() {
    local version=$1

    print_status $BLUE "Pushing image to ECR..."

    # Get ECR repository URI from foundations stack
    local foundations_stack_name="${PROJECT_NAME}-foundations"
    local ecr_uri=$(get_stack_output "$foundations_stack_name" "ECRRepositoryURI")
    if [[ -z "$ecr_uri" ]]; then
        print_status $RED "ERROR: Could not get ECR repository URI. Is the foundations stack deployed?"
        print_status $YELLOW "Deploy the foundations stack first with: ./scripts/deploy-foundations.sh"
        exit 1
    fi

    print_status $BLUE "ECR Repository: $ecr_uri"

    # Login to ECR
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ecr_uri"

    # Tag and push images
    docker tag "${PROJECT_NAME}:${version}" "${ecr_uri}:${version}"
    docker tag "${PROJECT_NAME}:${version}" "${ecr_uri}:latest"

    docker push "${ecr_uri}:${version}"
    docker push "${ecr_uri}:latest"

    print_status $GREEN "✓ Images pushed to ECR successfully"
    print_status $BLUE "Image URI: ${ecr_uri}:${version}"
}

# Function to trigger CodeBuild
trigger_codebuild() {
    local version=$1

    print_status $BLUE "Triggering CodeBuild..."

    print_status $GREEN "✓ Image pushed to ECR - automatic deployment will be triggered via EventBridge"
}

# Function to show deployment status
show_deployment_status() {
    print_status $BLUE "Checking deployment status..."

    # Get ALB URL from application stack
    local application_stack_name="${PROJECT_NAME}-application"
    local alb_url=$(get_stack_output "$application_stack_name" "ALBUrl")
    if [[ -n "$alb_url" ]]; then
        print_status $GREEN "Application URL: $alb_url"
    fi

    print_status $BLUE "Monitor deployments at: https://${REGION}.console.aws.amazon.com/codesuite/codedeploy/applications/${PROJECT_NAME}"
}

# Main function
main() {
    local version="$1"

    if [[ -z "$version" ]]; then
        print_status $RED "ERROR: Version argument is required"
        show_usage
        exit 1
    fi

    print_status $BLUE "=== ECS CodeDeploy Demo - Build and Deploy ==="
    print_status $BLUE "Version: $version"
    print_status $BLUE "Region: $REGION"
    print_status $BLUE "Mode: $([ "$LOCAL_TEST" == "true" ] && echo "Local Test" || echo "AWS Deployment")"
    echo ""

    # Check prerequisites
    check_prerequisites
    echo ""

    # Build image
    build_image "$version"
    echo ""

    # Test locally if requested
    if [[ "$LOCAL_TEST" == "true" ]]; then
        test_image_locally "$version"
        print_status $GREEN "=== LOCAL TEST COMPLETED ==="
        return 0
    fi

    # Push to ECR (if not build-only)
    if [[ "$BUILD_ONLY" != "true" ]]; then
        push_to_ecr "$version"
        echo ""

        # Show deployment status
        show_deployment_status
    else
        print_status $GREEN "✓ Build completed (build-only mode)"
    fi

    echo ""
    print_status $GREEN "=== BUILD AND DEPLOY COMPLETED ==="
}

# Parse command line arguments
BUILD_ONLY=false
LOCAL_TEST=false
NO_CACHE=false
WAIT_FOR_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_usage
            exit 0
            ;;
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --local-test)
            LOCAL_TEST=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --wait)
            WAIT_FOR_BUILD=true
            shift
            ;;
        --region)
            if [[ -z "${2:-}" ]]; then
                print_status $RED "ERROR: --region requires a value"
                exit 1
            fi
            REGION="$2"
            shift 2
            ;;
        -*)
            print_status $RED "ERROR: Unknown option $1"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "${VERSION:-}" ]]; then
                VERSION="$1"
            else
                print_status $RED "ERROR: Multiple version arguments provided"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Run main function
main "$VERSION"
