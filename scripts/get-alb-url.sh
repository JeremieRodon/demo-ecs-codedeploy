#!/bin/sh

# ECS CodeDeploy Demo - Get ALB URL Script
# This script retrieves the Application Load Balancer URL for the demo

set -e  # Exit on any error

# Configuration
PROJECT_NAME="ecs-codedeploy-demo"
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
    echo "  --stack-name NAME   Override stack name (default: ${PROJECT_NAME}-application)"
    echo "  --open              Open URL in default browser (macOS/Linux)"
    echo "  --health            Check health endpoint"
    echo "  --json              Output in JSON format"
    echo "  --quiet             Only output the URL"
    echo ""
    echo "Examples:"
    echo "  $0                  # Get ALB URL"
    echo "  $0 --open           # Get URL and open in browser"
    echo "  $0 --health         # Check application health"
    echo "  $0 --json           # Output in JSON format"
    echo ""
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_status $RED "ERROR: AWS CLI is not installed"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        print_status $RED "ERROR: AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
}

# Function to get stack output
get_stack_output() {
    local stack_name=$1
    local output_key=$2

    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# Function to get ALB information
get_alb_info() {
    local stack_name="${PROJECT_NAME}-application"

    if [[ -n "$CUSTOM_STACK_NAME" ]]; then
        stack_name="$CUSTOM_STACK_NAME"
    fi

    # Check if stack exists
    if ! aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" &> /dev/null; then
        print_status $RED "ERROR: Stack not found: $stack_name"
        print_status $YELLOW "Make sure the demo stack is deployed first."
        exit 1
    fi

    # Get ALB information
    local alb_url=$(get_stack_output "$stack_name" "ALBUrl")
    local alb_dns=$(get_stack_output "$stack_name" "ALBUrl" | cut -d'/' -f3)
    local alb_arn=""

    if [[ -z "$alb_url" ]]; then
        print_status $RED "ERROR: Could not retrieve ALB URL from stack: $stack_name"
        exit 1
    fi

    echo "$alb_url|$alb_dns|$alb_arn"
}

# Function to check application health
check_health() {
    local url=$1

    if [[ "$QUIET" != "true" ]]; then
        print_status $BLUE "Checking application health..."
    fi

    # Test main endpoint
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" "$url" --connect-timeout 10 --max-time 30 || echo "000")

    if [[ "$http_status" == "200" ]]; then
        if [[ "$QUIET" != "true" ]]; then
            print_status $GREEN "✓ Application is healthy (HTTP $http_status)"
        fi
        return 0
    else
        if [[ "$QUIET" != "true" ]]; then
            print_status $RED "✗ Application health check failed (HTTP $http_status)"
        fi
        return 1
    fi
}

# Function to get application version
get_app_version() {
    local url=$1

    # Try to extract version from the page content
    local version=$(curl -s "$url" --connect-timeout 10 --max-time 30 | grep -o 'v[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "unknown")
    echo "$version"
}

# Function to output JSON format
output_json() {
    local url=$1
    local dns=$2
    local arn=$3
    local health_status=$4
    local version=$5

    cat << EOF
{
  "url": "$url",
  "dns_name": "$dns",
  "arn": "$arn",
  "health_status": "$health_status",
  "version": "$version",
  "region": "$REGION",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Main function
main() {
    if [[ "$QUIET" != "true" ]]; then
        print_status $BLUE "=== ECS CodeDeploy Demo - ALB URL ==="
        print_status $BLUE "Region: $REGION"
        echo ""
    fi

    # Check prerequisites
    check_aws_cli

    # Get ALB information
    local alb_info=$(get_alb_info)
    IFS='|' read -r alb_url alb_dns alb_arn <<< "$alb_info"

    # Check health if requested
    local health_status="unknown"
    if [[ "$CHECK_HEALTH" == "true" ]]; then
        if check_health "$alb_url"; then
            health_status="healthy"
        else
            health_status="unhealthy"
        fi
    fi

    # Get application version if checking health
    local app_version="unknown"
    if [[ "$CHECK_HEALTH" == "true" && "$health_status" == "healthy" ]]; then
        app_version=$(get_app_version "$alb_url")
    fi

    # Output results
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json "$alb_url" "$alb_dns" "$alb_arn" "$health_status" "$app_version"
    elif [[ "$QUIET" == "true" ]]; then
        echo "$alb_url"
    else
        print_status $GREEN "Application Load Balancer URL: $alb_url"
        print_status $BLUE "DNS Name: $alb_dns"

        if [[ "$CHECK_HEALTH" == "true" ]]; then
            print_status $BLUE "Health Status: $health_status"
            if [[ "$app_version" != "unknown" ]]; then
                print_status $BLUE "Application Version: $app_version"
            fi
        fi

        echo ""
        print_status $YELLOW "You can access the application at: $alb_url"

        if [[ "$CHECK_HEALTH" != "true" ]]; then
            echo ""
            print_status $BLUE "To check application health, run:"
            print_status $BLUE "  $0 --health"
        fi
    fi

    # Open in browser if requested
    if [[ "$OPEN_BROWSER" == "true" ]]; then
        if [[ "$QUIET" != "true" ]]; then
            print_status $BLUE "Opening URL in default browser..."
        fi

        if command -v open &> /dev/null; then
            # macOS
            open "$alb_url"
        elif command -v xdg-open &> /dev/null; then
            # Linux
            xdg-open "$alb_url"
        elif command -v start &> /dev/null; then
            # Windows (Git Bash/WSL)
            start "$alb_url"
        else
            print_status $YELLOW "Could not detect browser command. Please open manually: $alb_url"
        fi
    fi
}

# Parse command line arguments
OPEN_BROWSER=false
CHECK_HEALTH=false
JSON_OUTPUT=false
QUIET=false
CUSTOM_STACK_NAME=""

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
        --stack-name)
            if [[ -z "${2:-}" ]]; then
                print_status $RED "ERROR: --stack-name requires a value"
                exit 1
            fi
            CUSTOM_STACK_NAME="$2"
            shift 2
            ;;
        --open)
            OPEN_BROWSER=true
            shift
            ;;
        --health)
            CHECK_HEALTH=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --quiet)
            QUIET=true
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

# Run main function
main
