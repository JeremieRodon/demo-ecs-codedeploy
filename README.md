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
- **ECR Stack**: Container registry (deployed first)
- **Main Stack**:
  - **VPC**: Simple 2-AZ setup with public subnets
  - **ECS Cluster**: Fargate-only with 2 tasks
  - **Application Load Balancer**: Blue/Green target groups
  - **CodeDeploy Application**: Manages Blue/Green deployments
  - **EventBridge Rule**: Triggers on ECR push events
  - **Lambda Function**: Creates new task definition and triggers deployment

### Application
- **Simple Apache Web Server**: Displays webpage with version information
- **Multiple Versions**: v1.0 (blue), v2.0 (orange), v3.0 (dark), v4.0 (failure test) themes
- **Integration Testing**: Lambda function validates deployments via test listener (port 8080)

## Demo Flow (7 minutes)

1. **Create ECR Repository**: Deploy ECR stack first
2. **Build and Deploy v1.0**: Build and push initial image
3. **Deploy Main Infrastructure**: Deploy the main demo stack
4. **Push v2.0**: ECR push automatically triggers Blue/Green deployment with integration tests
5. **Watch Magic**: CodeDeploy seamlessly switches traffic after tests pass
6. **Push v3.0**: Another automatic deployment to show reliability
7. **Push v4.0**: Demonstrates automatic rollback when integration tests fail

## Prerequisites

- AWS CLI configured with appropriate permissions
- Docker (for local testing)
- Basic IAM permissions for CloudFormation, ECS, CodeDeploy, ECR, Lambda, and EventBridge

## Quick Start

1. **Create ECR Repository** (~1 minute):
   ```bash
   cd cloudformation && ./deploy-ecr.sh
   ```

2. **Build and Deploy v1.0**:
   ```bash
   ../scripts/build-and-deploy.sh v1.0
   ```

3. **Deploy Main Infrastructure** (~5 minutes):
   ```bash
   ./deploy.sh
   ```

4. **Access Application**:
   ```bash
   ../scripts/get-alb-url.sh --open
   ```

5. **Trigger Automatic Deployment** (push v2.0 to see magic happen):
   ```bash
   ../scripts/build-and-deploy.sh v2.0
   ```
   → ECR push → EventBridge → Lambda → CodeDeploy → Blue/Green deployment!

6. **Try Another Version**:
   ```bash
   ../scripts/build-and-deploy.sh v3.0  # Dark theme
   ```

7. **Test Failure and Rollback** (demonstrates integration testing):
   ```bash
   ../scripts/build-and-deploy.sh v4.0  # This will fail integration tests and rollback!
   ```

## Directory Structure

```
demo-ecs-codedeploy/
├── README.md                        # This file
├── cloudformation/                  # CloudFormation templates
│   ├── ecr-stack.yaml              # ECR repository (deploy first)
│   ├── demo-stack.yaml             # Main infrastructure
│   ├── deploy-ecr.sh               # Deploy ECR stack
│   ├── deploy.sh                   # Deploy main stack
│   └── cleanup.sh                  # Delete both stacks
├── application/                     # Application source code
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
    ├── get-alb-url.sh              # Get ALB URL and health check
    └── validate-setup.sh           # Validate deployment status
```

## Key Demo Points

- **🚀 Zero-Downtime**: Blue/Green deployment ensures no service interruption
- **🤖 Fully Automated**: ECR push → EventBridge → Lambda → CodeDeploy
- **🧪 Integration Testing**: Lambda function validates deployments before traffic switch
- **🔄 Automatic Rollback**: Failed integration tests trigger automatic rollback
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
# Step 1: Create ECR repository (~1 minute)
cd cloudformation && ./deploy-ecr.sh

# Step 2: Build and push v1.0 (~1 minute)
../scripts/build-and-deploy.sh v1.0

# Step 3: Deploy main infrastructure (~3 minutes)
./deploy.sh

# Step 4: Show running application
../scripts/get-alb-url.sh --open
# You should see the blue v1.0 theme

# Step 5: Push v2.0 and watch magic happen! (~1 minute)
../scripts/build-and-deploy.sh v2.0
# → ECR push → EventBridge → Lambda → CodeDeploy → Blue/Green deployment!
# Refresh browser to see orange v2.0 theme after deployment completes

# Step 6: Push v3.0 for dramatic effect
../scripts/build-and-deploy.sh v3.0
# → Another automatic deployment
# Refresh browser to see dark cyberpunk v3.0 theme

# Step 7: Demonstrate failure and rollback with v4.0
../scripts/build-and-deploy.sh v4.0
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
cd cloudformation && ./cleanup.sh
```

This enhanced cleanup script will:
- 🗂️ **Clean up all task definitions** (created outside CloudFormation)
- 🗑️ **Delete both CloudFormation stacks**
- 📦 **Empty and delete ECR repository**
- 🔍 **Verify complete cleanup**

### Task Definition Only Cleanup

If you only need to clean up task definitions (useful during development):

```bash
cd scripts && ./cleanup-task-definitions.sh
```

Options available:
- `--dry-run` - See what would be deleted without making changes
- `--force` - Skip confirmation prompts
- `--family NAME` - Clean up different task definition family

## Troubleshooting

- **Stack fails to deploy**: Check IAM permissions
- **Main stack fails**: Ensure ECR stack is deployed first
- **App not accessible**: Wait 2-3 minutes for ECS tasks to start, run `./scripts/validate-setup.sh`
- **Deployment not triggered**: Check EventBridge rule in AWS console
- **Integration test fails**: Check Lambda function logs in CloudWatch
- **v4.0 doesn't rollback**: Check CodeDeploy application logs and Lambda execution
- **Build fails**: Ensure Docker is running locally
- **Not sure what's wrong?**: Run `./scripts/validate-setup.sh` for detailed diagnostics

## What Makes This Different

This demo focuses on the **core value proposition**:
- ECR push automatically triggers safe Blue/Green deployments with integration testing
- Lambda-based quality gates ensure deployment safety
- Automatic rollback when tests fail (demonstrated with v4.0)
- No complex CI/CD pipelines to explain
- No CodeBuild complexity
- Just the essential: **Push → Event → Test → Deploy (or Rollback)**

Perfect for showing stakeholders how modern deployment automation works with built-in safety!
