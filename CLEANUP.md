# Cleanup Guide

This document explains the comprehensive cleanup process for the ECS CodeDeploy demo, including the removal of all resources created during the demonstration.

## Overview

The demo creates several types of resources:
- **CloudFormation managed**: VPC, ECS cluster, ALB, CodeDeploy application, CodePipeline, Lambda functions
- **Dynamically created**: ECS task definitions (created by CodePipeline during deployments)
- **ECR resources**: Docker images in the repository

The enhanced cleanup process ensures all resources are properly removed, including those created outside of CloudFormation.

## Complete Cleanup (Recommended)

### Single Command Cleanup

```bash
./cleanup.sh
```

This comprehensive script performs the following actions:

1. **🗂️ Task Definition Cleanup**
   - Lists all task definitions in the project family
   - Deregisters all task definitions (makes them inactive)
   - Deletes all task definitions (permanent removal)
   - Verifies cleanup completion

2. **🗑️ CloudFormation Stack Deletion**
   - Deletes the application infrastructure stack
   - Deletes the foundations infrastructure stack
   - Waits for complete deletion
   - Handles dependencies automatically

3. **📦 ECR Repository Cleanup**
   - Empties the ECR repository (removes all images)
   - Removes the repository as part of foundations stack deletion

4. **🔍 Verification**
   - Checks for remaining task definitions
   - Verifies all resources are cleaned up
   - Reports any manual cleanup needed

### Expected Output

```
🧹 Cleaning up ECS CodeDeploy Demo...
🗂️  Cleaning up task definitions...
📋 Found 5 task definition(s) to clean up:
  ✅ Deregistered: ecs-codedeploy-demo:1
  ✅ Deregistered: ecs-codedeploy-demo:2
  ✅ Deregistered: ecs-codedeploy-demo:3
  ✅ Deregistered: ecs-codedeploy-demo:4
  ✅ Deregistered: ecs-codedeploy-demo:5
🗑️  Deleting application stack...
⏳ Waiting for application stack deletion to complete...
✅ Application stack deleted successfully!
📦 Emptying ECR repository...
🗑️  Deleting foundations stack...
⏳ Waiting for foundations stack deletion to complete...
✅ Foundations stack deleted successfully!
🔍 Verifying cleanup completion...
✅ All task definitions cleaned up successfully
✅ No active deployments found
🎉 Cleanup completed!
```

## Selective Cleanup Options

### Task Definitions Only

Clean up only the task definitions without touching CloudFormation stacks:

```bash
./scripts/cleanup-task-definitions.sh
```

**Use cases:**
- During development when testing multiple deployments
- When you want to reset task definitions but keep infrastructure
- Troubleshooting deployment issues

**Options:**
- `--dry-run` - Preview what would be deleted
- `--force` - Skip confirmation prompts
- `--family NAME` - Specify different task definition family

### Preview Mode

See what would be cleaned up without making changes:

```bash
./scripts/cleanup-task-definitions.sh --dry-run
```

## Troubleshooting Cleanup Issues

### Common Issues

**Task definitions won't delete:**
- Some task definitions might be in use by active ECS services
- Wait for ECS service to be deleted first
- Check ECS console for any running tasks

**CloudFormation stack deletion fails:**
- Resources might be in use by other services
- Check dependencies in AWS console
- Look for ECS services still running

**ECR repository not empty:**
- Images might be in use by running containers
- Stop all containers using the images
- Manually delete images from ECR console if needed

### Manual Cleanup Steps

If automatic cleanup fails, follow these steps:

1. **Stop ECS Services**
   ```bash
   aws ecs update-service \
     --cluster ecs-codedeploy-demo \
     --service ecs-codedeploy-demo \
     --desired-count 0
   ```

2. **Delete Task Definitions Manually**
   - Go to ECS Console → Task Definitions
   - Select the `ecs-codedeploy-demo` family
   - Select all revisions and delete

3. **Empty ECR Repository**
   ```bash
   aws ecr batch-delete-image \
     --repository-name ecs-codedeploy-demo \
     --image-ids imageTag=v1.0 imageTag=v2.0 imageTag=v3.0 imageTag=v4.0 imageTag=latest
   ```

4. **Force Delete CloudFormation Stacks**
   ```bash
   aws cloudformation delete-stack --stack-name ecs-codedeploy-demo-application
   aws cloudformation delete-stack --stack-name ecs-codedeploy-demo-foundations
   ```

### Verification Commands

Check if cleanup was successful:

```bash
# Check task definitions
aws ecs list-task-definitions --family-prefix ecs-codedeploy-demo

# Check CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE

# Check ECR repositories
aws ecr describe-repositories --repository-names ecs-codedeploy-demo
```

## Why Enhanced Cleanup is Necessary

### CloudFormation Limitations

CloudFormation doesn't track resources created dynamically by Lambda functions:
- Task definitions created during deployments
- Task definition revisions from multiple builds
- Resources created by AWS services (like CodeDeploy)

### Task Definition Accumulation

Each deployment creates a new task definition revision:
- Initial CloudFormation deployment → revision 1
- v1.0 deployment → revision 2
- v2.0 deployment → revision 3
- v3.0 deployment → revision 4
- v4.0 deployment → revision 5
- Failed deployments → additional revisions

Without cleanup, these accumulate and:
- Clutter the AWS console
- May hit AWS service limits
- Can interfere with future deployments

## Best Practices

### During Development

1. **Use task definition cleanup frequently:**
   ```bash
   ./scripts/cleanup-task-definitions.sh
   ```

2. **Preview changes before cleanup:**
   ```bash
   ./scripts/cleanup-task-definitions.sh --dry-run
   ```

3. **Clean up after each demo:**
   ```bash
   cd cloudformation && ./cleanup.sh
   ```

### For Production

1. **Implement retention policies** for task definitions
2. **Use automated cleanup** in CI/CD pipelines
3. **Monitor resource usage** to prevent accumulation
4. **Document cleanup procedures** for your team

## Cost Considerations

Resources that incur costs:
- **ECS tasks**: Charged per vCPU/memory/hour
- **ALB**: Charged per hour + data processing
- **ECR storage**: Charged per GB stored
- **Lambda invocations**: Charged per invocation
- **CloudWatch logs**: Charged per GB stored
- **CodePipeline**: Charged per pipeline execution

The cleanup script ensures all these resources are properly removed to avoid ongoing charges.

## Automation

### Scheduled Cleanup

You can automate cleanup using cron jobs:

```bash
# Add to crontab to cleanup daily
0 2 * * * /path/to/demo/scripts/cleanup-task-definitions.sh --force
```

### CI/CD Integration

Include cleanup in your CI/CD pipeline:

```yaml
# Example GitHub Actions step
- name: Cleanup Demo Resources
  run: |
    ./cleanup.sh
```

## Recovery

If you accidentally run cleanup and need to restore:

1. **Redeploy the infrastructure:**
   ```bash
   ./deploy.sh
   ```

2. **Rebuild and deploy applications:**
   ```bash
   ./scripts/build-and-deploy.sh v2.0
   ./scripts/build-and-deploy.sh v3.0
   ```

The demo is designed to be easily reproducible, so full recovery takes only a few minutes.