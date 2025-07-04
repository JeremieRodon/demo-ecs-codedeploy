# ECS CodeDeploy Demo

This demo showcases automatic Blue/Green deployments for ECS applications triggered by ECR image pushes using EventBridge and AWS CodeDeploy.

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│   Developer     │    │   Amazon ECR    │    │   EventBridge    │
│   Pushes Image  │───▶│   Image Push    │───▶│   Rule Triggers  │
└─────────────────┘    └─────────────────┘    └──────────────────┘
                                                         │
                                                         ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Application    │◀───│   CodeDeploy     │◀───│   Lambda        │
│  Load Balancer  │    │  Blue/Green      │    │   Function      │
└─────────────────┘    │  Deployment      │    └─────────────────┘
         │             └──────────────────┘
         ▼
┌─────────────────┐
│   ECS Cluster   │
│   2x Fargate    │
│   Tasks         │
└─────────────────┘
```

## Components

### Infrastructure (Two CloudFormation Stacks)
- **Foundations Stack**: Core infrastructure (deployed first)
  - **VPC**: Simple 2-AZ setup with public subnets
  - **ECS Cluster**: Fargate-only cluster
  - **ECR Repository**: Container registry
  - **Lambda Functions**: Custom resource helpers
- **Application Stack**: Application infrastructure
  - **Application Load Balancer**: Blue/Green target groups
  - **ECS Service**: Fargate-based with 2 tasks
  - **CodeDeploy Application**: Manages Blue/Green deployments
  - **CodePipeline**: Automated deployment pipeline
  - **EventBridge Rule**: Triggers on ECR push events
  - **Lambda Function**: Integration testing for deployments

### Application
- **Simple Apache Web Server**: Displays webpage with version information
- **Multiple Versions**: v1.0 (blue), v2.0 (orange), v3.0 (dark), v4.0 (failure test) themes
- **Integration Testing**: Lambda function validates deployments via test listener (port 8080)

## Demo Flow (7 minutes)

1. **Deploy Foundations**: Deploy foundations stack (VPC, ECS cluster, ECR)
2. **Build and Deploy v1.0**: Build and push initial image
3. **Deploy Application Infrastructure**: Deploy the application stack
4. **Push v2.0**: ECR push automatically triggers Blue/Green deployment with integration tests
5. **Watch Magic**: CodeDeploy seamlessly switches traffic after tests pass
6. **Push v3.0**: Another automatic deployment to show reliability
7. **Push v4.0**: Demonstrates automatic rollback when integration tests fail

## CodePipeline Sequential Deployment Advantage

One of the major benefits of using CodePipeline (instead of Lambda triggers) is **strict deployment ordering**:

- **Sequential Processing**: CodePipeline ensures deployments happen one at a time
- **No Race Conditions**: Rapid successive ECR pushes won't cause conflicts
- **Reliable Queuing**: New deployments wait for current one to complete before starting
- **Crash Prevention**: Eliminates Lambda crashes from attempting concurrent CodeDeploy operations

**Example Scenario**:
```bash
# These rapid deployments are now safe:
./scripts/build-and-deploy.sh v2.0
./scripts/build-and-deploy.sh v3.0  # Waits for v2.0 to complete
./scripts/build-and-deploy.sh v2.0  # Waits for v3.0 to complete
```

Previously with Lambda triggers, rapid deployments would cause failures. Now CodePipeline gracefully handles the queue.

## Prerequisites

- AWS CLI configured with appropriate permissions
- Docker (for local testing)
- Basic IAM permissions for CloudFormation, ECS, CodeDeploy, ECR, Lambda, and EventBridge

## Quick Start

1. **Deploy Complete Infrastructure** (~6 minutes):
   ```bash
   ./deploy.sh
   ```
   This automatically:
   - Deploys foundations stack (VPC, ECS cluster, ECR)
   - Builds and pushes v1.0 image (if ECR is empty)
   - Deploys application stack (ALB, CodeDeploy, CodePipeline)

2. **Access Application**:
   ```bash
   ./scripts/get-alb-url.sh --open
   ```

3. **Trigger Automatic Deployment** (push v2.0 to see magic happen):
   ```bash
   ./scripts/build-and-deploy.sh v2.0
   ```
   → ECR push → EventBridge → CodePipeline → CodeDeploy → Blue/Green deployment!

4. **Try Another Version**:
   ```bash
   ./scripts/build-and-deploy.sh v3.0  # Dark theme
   ```

5. **Test Failure and Rollback** (demonstrates integration testing):
   ```bash
   ./scripts/build-and-deploy.sh v4.0  # This will fail integration tests and rollback!
   ```

## Directory Structure

```
demo-ecs-codedeploy/
├── README.md                       # This file
├── deploy.sh                       # Complete deployment script
├── cleanup.sh                      # Complete cleanup script
├── cloudformation/                 # CloudFormation templates
│   ├── 1-demo-fundations.yaml      # Foundations stack (VPC, ECS, ECR)
│   └── 2-demo-application.yaml     # Application stack (ALB, CodeDeploy, Pipeline)
├── application/                    # Application source code
│   ├── v1.0/                       # Blue gradient theme
│   │   ├── Dockerfile
│   │   └── index.html
│   ├── v2.0/                       # Orange gradient theme
│   │   ├── Dockerfile
│   │   └── index.html
│   ├── v3.0/                       # Dark cyberpunk theme
│   │   ├── Dockerfile
│   │   └── index.html
│   ├── v4.0/                       # Failure test version
│   │   ├── Dockerfile
│   │   └── index.html
│   └── buildspec.yml               # (Not used - simplified approach)
└── scripts/                        # Helper scripts
    ├── build-and-deploy.sh         # Build and push to ECR
    ├── cleanup-task-definitions.sh # Clean up ECS task definitions
    ├── deploy-application.sh       # Deploy application stack
    ├── deploy-foundations.sh       # Deploy foundations stack
    ├── get-alb-url.sh              # Get ALB URL and health check
    └── validate-setup.sh           # Validate deployment status
```

## Key Demo Points

- **🚀 Zero-Downtime**: Blue/Green deployment ensures no service interruption
- **🤖 Fully Automated**: ECR push → EventBridge → CodePipeline → CodeDeploy
- **🧪 Integration Testing**: Lambda function validates deployments before traffic switch
- **🔄 Automatic Rollback**: Failed integration tests trigger automatic rollback
- **⚡ Sequential Deployments**: CodePipeline ensures safe ordering of rapid deployments
- **👀 Visual Impact**: Each version has completely different styling
- **⚡ Fast Setup**: Two simple CloudFormation stacks, deploy in ~6 minutes
- **🔄 Repeatable**: Push any version to trigger automatic deployment
- **📊 Observable**: Watch real deployments happen in AWS console

## Visual Versions

- **v1.0**: 🔵 Blue gradient (professional look)
- **v2.0**: 🟠 Orange gradient (modern animations)
- **v3.0**: ⚫ Dark cyberpunk (matrix effects)
- **v4.0**: 🔴 Red failure theme (triggers integration test failure)

## Perfect for Demos Because...

- **Quick Setup**: Two simple commands deploy everything
- **Visual Impact**: Dramatic color changes make deployments obvious
- **Real AWS Services**: Uses actual CodeDeploy, not simulated
- **Integration Testing**: Shows real-world deployment validation
- **Failure Demonstration**: v4.0 shows automatic rollback in action
- **Audience Friendly**: Easy to explain and understand
- **Reliable**: Simplified architecture reduces failure points
- **Cost Effective**: Uses minimal resources, easy to clean up

## Demo Script (8 minutes)

```bash
# Step 1: Deploy complete infrastructure (~6 minutes)
./deploy.sh
# This automatically:
# - Deploys foundations stack (VPC, ECS cluster, ECR)
# - Builds and pushes v1.0 image (if ECR is empty)
# - Deploys application stack (ALB, CodeDeploy, CodePipeline)

# Step 2: Show running application
./scripts/get-alb-url.sh --open
# You should see the blue v1.0 theme

# Step 3: Push v2.0 and watch magic happen! (~1 minute)
./scripts/build-and-deploy.sh v2.0
# → ECR push → EventBridge → CodePipeline → CodeDeploy → Blue/Green deployment!
# Refresh browser to see orange v2.0 theme after deployment completes

# Step 4: Push v3.0 for dramatic effect
./scripts/build-and-deploy.sh v3.0
# → Another automatic deployment
# Refresh browser to see dark cyberpunk v3.0 theme

# Step 5: Demonstrate failure and rollback with v4.0
./scripts/build-and-deploy.sh v4.0
# → This will fail integration tests and automatically rollback!
# Check AWS console to see the rollback in action
```

## Validation

Check if everything is set up correctly:

```bash
./scripts/validate-setup.sh
```

This script will:
- ✅ Verify both stacks are deployed
- 📦 Check ECR repository has images
- 🚀 Validate ECS service health
- 🌐 Test application availability
- 🧪 Validate integration test function
- 📋 Show next steps if issues found

## Cleanup

### Complete Cleanup (Recommended)

Single command cleans up everything including task definitions:

```bash
./cleanup.sh
```

This enhanced cleanup script will:
- 🗂️ **Clean up all task definitions** (created outside CloudFormation)
- 🗑️ **Delete both CloudFormation stacks** (foundations and application)
- 📦 **Empty and delete ECR repository**
- 🔍 **Verify complete cleanup**

### Task Definition Only Cleanup

If you only need to clean up task definitions (useful during development):

```bash
./scripts/cleanup-task-definitions.sh
```

Options available:
- `--dry-run` - See what would be deleted without making changes
- `--force` - Skip confirmation prompts
- `--family NAME` - Clean up different task definition family

## Troubleshooting

- **Stack fails to deploy**: Check IAM permissions
- **Application stack fails**: Ensure foundations stack is deployed first
- **App not accessible**: Wait 2-3 minutes for ECS tasks to start, run `./scripts/validate-setup.sh`
- **Deployment not triggered**: Check EventBridge rule and CodePipeline in AWS console
- **Integration test fails**: Check Lambda function logs in CloudWatch
- **v4.0 doesn't rollback**: Check CodeDeploy application logs and Lambda execution
- **Build fails**: Ensure Docker is running locally
- **Not sure what's wrong?**: Run `./scripts/validate-setup.sh` for detailed diagnostics

## What Makes This Different

This demo focuses on the **core value proposition**:
- ECR push automatically triggers safe Blue/Green deployments with integration testing
- CodePipeline orchestrates the entire deployment workflow with strict ordering
- Lambda-based quality gates ensure deployment safety
- Automatic rollback when tests fail (demonstrated with v4.0)
- EventBridge-driven automation for real-time deployment triggers
- **Sequential deployment safety**: No race conditions from rapid successive pushes
- Complete infrastructure-as-code with CloudFormation
- Just the essential: **Push → Event → Pipeline → Test → Deploy (or Rollback)**

Perfect for showing stakeholders how modern deployment automation works with built-in safety and reliability!
