#!/bin/sh

# ECS CodeDeploy Demo - Task Definition Cleanup Script
# This script cleans up all task definitions for the project family

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
    echo "  --family FAMILY     Override task definition family (default: $PROJECT_NAME)"
    echo "  --dry-run           Show what would be deleted without actually deleting"
    echo "  --force             Skip confirmation prompts"
    echo ""
    echo "Examples:"
    echo "  $0                           # Clean up with confirmation"
    echo "  $0 --dry-run                 # Show what would be cleaned up"
    echo "  $0 --force                   # Clean up without confirmation"
    echo "  $0 --family my-app           # Clean up different family"
    echo ""
    echo "This script will:"
    echo "  1. List all task definitions in the family"
    echo "  2. Deregister all task definitions"
    echo "  3. Delete all task definitions (permanent removal)"
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
}

# Function to list task definitions
list_task_definitions() {
    local family=$1

    aws ecs list-task-definitions \
        --family-prefix "$family" \
        --region "$REGION" \
        --query 'taskDefinitionArns[]' \
        --output text 2>/dev/null || echo ""
}

# Function to get task definition details
get_task_definition_details() {
    local arn=$1

    local revision=$(aws ecs describe-task-definition \
        --task-definition "$arn" \
        --region "$REGION" \
        --query 'taskDefinition.revision' \
        --output text 2>/dev/null || echo "unknown")

    local status=$(aws ecs describe-task-definition \
        --task-definition "$arn" \
        --region "$REGION" \
        --query 'taskDefinition.status' \
        --output text 2>/dev/null || echo "unknown")

    local created=$(aws ecs describe-task-definition \
        --task-definition "$arn" \
        --region "$REGION" \
        --query 'taskDefinition.registeredAt' \
        --output text 2>/dev/null || echo "unknown")

    echo "$revision|$status|$created"
}

# Function to display task definitions
display_task_definitions() {
    local task_def_arns=$1

    if [[ -z "$task_def_arns" || "$task_def_arns" == "None" ]]; then
        return 1
    fi

    print_status $BLUE "Task definitions found:"
    echo ""
    printf "%-10s %-12s %-25s %s\n" "Revision" "Status" "Created" "ARN"
    printf "%-10s %-12s %-25s %s\n" "--------" "------" "-------" "---"

    echo "$task_def_arns" | tr '\t' '\n' | while read -r arn; do
        if [[ -n "$arn" ]]; then
            local details=$(get_task_definition_details "$arn")
            IFS='|' read -r revision status created <<< "$details"
            printf "%-10s %-12s %-25s %s\n" "$revision" "$status" "$created" "$(basename "$arn")"
        fi
    done

    echo ""
}

# Function to deregister task definitions
deregister_task_definitions() {
    local task_def_arns=$1
    local dry_run=$2

    print_status $YELLOW "Deregistering task definitions..."

    local deregister_count=0
    local deregister_failed=0

    echo "$task_def_arns" | tr '\t' '\n' | while read -r arn; do
        if [[ -n "$arn" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                print_status $BLUE "  [DRY RUN] Would deregister: $(basename "$arn")"
                deregister_count=$((deregister_count + 1))
            else
                if aws ecs deregister-task-definition \
                    --task-definition "$arn" \
                    --region "$REGION" \
                    --output text > /dev/null 2>&1; then
                    print_status $GREEN "  ✅ Deregistered: $(basename "$arn")"
                    deregister_count=$((deregister_count + 1))
                else
                    print_status $RED "  ❌ Failed to deregister: $(basename "$arn")"
                    deregister_failed=$((deregister_failed + 1))
                fi
            fi
        fi
    done

    if [[ "$dry_run" != "true" ]]; then
        print_status $BLUE "Deregistration summary: $deregister_count succeeded, $deregister_failed failed"
    fi

    return 0
}

# Function to delete task definitions
delete_task_definitions() {
    local task_def_arns=$1
    local dry_run=$2

    print_status $YELLOW "Deleting task definitions..."

    local delete_count=0
    local delete_failed=0

    echo "$task_def_arns" | tr '\t' '\n' | while read -r arn; do
        if [[ -n "$arn" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                print_status $BLUE "  [DRY RUN] Would delete: $(basename "$arn")"
                delete_count=$((delete_count + 1))
            else
                if aws ecs delete-task-definitions \
                    --task-definitions "$arn" \
                    --region "$REGION" \
                    --output text > /dev/null 2>&1; then
                    print_status $GREEN "  ✅ Deleted: $(basename "$arn")"
                    delete_count=$((delete_count + 1))
                else
                    print_status $YELLOW "  ⚠️  Could not delete: $(basename "$arn") (may need manual cleanup)"
                    delete_failed=$((delete_failed + 1))
                fi
            fi
        fi
    done

    if [[ "$dry_run" != "true" ]]; then
        print_status $BLUE "Deletion summary: $delete_count succeeded, $delete_failed failed"
    fi

    return 0
}

# Function to confirm action
confirm_action() {
    local family=$1
    local count=$2

    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    echo ""
    print_status $YELLOW "⚠️  WARNING: This will permanently delete $count task definition(s) from family '$family'"
    print_status $YELLOW "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status $BLUE "Operation cancelled by user"
        exit 0
    fi
}

# Main function
main() {
    local family="$PROJECT_NAME"
    local dry_run=false

    if [[ -n "$CUSTOM_FAMILY" ]]; then
        family="$CUSTOM_FAMILY"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run=true
    fi

    print_status $BLUE "=== ECS Task Definition Cleanup ==="
    print_status $BLUE "Family: $family"
    print_status $BLUE "Region: $REGION"
    if [[ "$dry_run" == "true" ]]; then
        print_status $YELLOW "Mode: DRY RUN (no changes will be made)"
    fi
    echo ""

    # Check prerequisites
    check_prerequisites

    # List task definitions
    print_status $BLUE "Searching for task definitions in family: $family"
    local task_def_arns=$(list_task_definitions "$family")

    if [[ -z "$task_def_arns" || "$task_def_arns" == "None" ]]; then
        print_status $GREEN "✅ No task definitions found for family: $family"
        print_status $BLUE "Nothing to clean up!"
        exit 0
    fi

    local task_count=$(echo "$task_def_arns" | wc -w)
    print_status $GREEN "Found $task_count task definition(s)"
    echo ""

    # Display task definitions
    display_task_definitions "$task_def_arns"

    # Confirm action (unless dry run or force)
    if [[ "$dry_run" != "true" ]]; then
        confirm_action "$family" "$task_count"
    fi

    # Deregister task definitions
    deregister_task_definitions "$task_def_arns" "$dry_run"

    # Wait for propagation (unless dry run)
    if [[ "$dry_run" != "true" ]]; then
        print_status $BLUE "⏳ Waiting for deregistration to propagate..."
        sleep 3
    fi

    # Delete task definitions
    delete_task_definitions "$task_def_arns" "$dry_run"

    # Final verification (unless dry run)
    if [[ "$dry_run" != "true" ]]; then
        echo ""
        print_status $BLUE "🔍 Verifying cleanup..."
        local remaining=$(list_task_definitions "$family")
        local remaining_count=0

        if [[ -n "$remaining" && "$remaining" != "None" ]]; then
            remaining_count=$(echo "$remaining" | wc -w)
        fi

        if [[ $remaining_count -eq 0 ]]; then
            print_status $GREEN "✅ All task definitions cleaned up successfully!"
        else
            print_status $YELLOW "⚠️  $remaining_count task definition(s) still exist"
            print_status $BLUE "   Manual cleanup may be required via AWS Console"
        fi
    fi

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        print_status $BLUE "🔍 Dry run completed - no changes made"
        print_status $BLUE "Run without --dry-run to perform actual cleanup"
    else
        print_status $GREEN "🎉 Task definition cleanup completed!"
    fi
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
CUSTOM_FAMILY=""

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
        --family)
            if [[ -z "${2:-}" ]]; then
                print_status $RED "ERROR: --family requires a value"
                exit 1
            fi
            CUSTOM_FAMILY="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
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
main "$@"
