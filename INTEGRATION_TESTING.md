# Integration Testing Architecture

This document explains the integration testing capabilities added to the ECS CodeDeploy demo, including how the Lambda-based quality gates work and how to use them effectively.

## Overview

The enhanced demo includes automatic integration testing that validates deployments before traffic is switched to the new version. This prevents bad deployments from reaching production and demonstrates real-world deployment safety practices.

## Architecture Components

### 1. Integration Test Lambda Function

**Function Name**: `{ProjectName}-integration-test`
**Runtime**: Python 3.9
**Timeout**: 5 minutes
**Trigger**: CodeDeploy lifecycle hook (`BeforeAllowTraffic`)

**Key Features**:
- Tests the new deployment via the ALB test listener (port 8080)
- Performs multiple validation checks
- Reports success/failure back to CodeDeploy
- Triggers automatic rollback on failure

### 2. CodeDeploy Lifecycle Hooks

The deployment configuration uses the `AfterAllowTestTraffic` hook to run integration tests after test traffic is routed but before switching production traffic to the new version.

**Hook Configuration**:
```yaml
Hooks:
  - AfterAllowTestTraffic: {IntegrationTestFunctionName}
```

**Process Flow**:
1. New tasks start in Green target group
2. ALB test listener (port 8080) routes to Green targets
3. CodeDeploy allows test traffic to flow to Green targets
4. CodeDeploy triggers Lambda function to validate the deployment
5. Lambda tests the application via port 8080
6. Based on test results:
   - **Success**: Production traffic switches to Green (deployment completes)
   - **Failure**: Deployment rolls back to Blue (previous version)

### 3. Test Listener Setup

- **Production Listener**: Port 80 (Blue target group initially)
- **Test Listener**: Port 8080 (Green target group for testing)

This allows testing the new version without affecting production traffic.

## Integration Test Validation

The Lambda function performs three categories of tests:

### 1. Connectivity Test
- Verifies the application responds on port 8080
- Checks HTTP status code is 200
- Ensures basic connectivity to new deployment

### 2. Content Validation
- Validates expected content is present
- Checks for failure triggers (used by v4.0 demo)
- Ensures application loaded correctly

### 3. Performance Test
- Measures response time
- Fails if response time > 5 seconds
- Validates application performance under test conditions

## Test Results and Actions

| Test Result | CodeDeploy Action | Description |
|-------------|-------------------|-------------|
| All Pass | Continue Deployment | Traffic switches to new version |
| Any Fail | Automatic Rollback | Traffic remains on previous version |
| Lambda Error | Automatic Rollback | Deployment fails due to test infrastructure issues |

## Application Versions and Testing

### v1.0, v2.0, v3.0 - Normal Versions
- Pass all integration tests
- Deploy successfully with zero downtime
- Demonstrate successful Blue/Green deployments

### v4.0 - Failure Test Version
- Contains `TEST_FAILURE_TRIGGER` marker
- **Intentionally fails** content validation test
- Demonstrates automatic rollback capability
- Shows integration testing preventing bad deployments

## Using Integration Testing

### Deploy Successful Version
```bash
./scripts/build-and-deploy.sh v2.0
```
**Expected Result**: Tests pass, deployment succeeds

### Deploy Failure Version
```bash
./scripts/build-and-deploy.sh v4.0
```
**Expected Result**: Tests fail, automatic rollback occurs

## Monitoring and Debugging

### CloudWatch Logs
- Lambda execution logs: `/aws/lambda/{ProjectName}-integration-test`
- CodeDeploy deployment logs: Available in CodeDeploy console

### Useful AWS Console Views
1. **CodeDeploy Application**: Monitor deployment status and history
2. **Lambda Function**: View test execution logs and metrics
3. **ECS Service**: Monitor task health and deployment progress
4. **ALB Target Groups**: Check Blue/Green target health

### Common Debug Commands
```bash
# Check deployment status
aws deploy get-deployment --deployment-id {deployment-id}

# View Lambda logs
aws logs tail /aws/lambda/{project-name}-integration-test --follow

# Validate overall setup
./scripts/validate-setup.sh
```

## Configuration Options

### Environment Variables (Lambda)
- `ALB_DNS_NAME`: Load balancer DNS name for testing
- `TEST_PORT`: Port for test listener (default: 8080)

### CodeDeploy Configuration
- **Deployment Config**: `CodeDeployDefault.ECSCanary10Percent5Minutes`
- **Auto Rollback**: Enabled for deployment failures
- **Termination Wait**: 5 minutes after successful deployment

## Best Practices

### 1. Test Design
- Keep tests fast (< 30 seconds total)
- Test critical functionality only
- Include performance validation
- Design for both positive and negative cases

### 2. Failure Handling
- Always report status back to CodeDeploy
- Log detailed failure reasons
- Implement timeout handling
- Consider retry logic for transient failures

### 3. Monitoring
- Set up CloudWatch alarms for test failures
- Monitor test execution duration
- Track rollback frequency
- Alert on repeated test failures

## Security Considerations

### IAM Permissions
- Lambda has minimal required permissions
- CodeDeploy can invoke Lambda function
- No unnecessary cross-service access

### Network Security
- Tests run within VPC if configured
- ALB security groups control access
- Lambda respects VPC networking rules

## Extending the Integration Tests

### Adding New Test Types
1. Modify Lambda function code in CloudFormation template
2. Add new test logic to `lambda_handler`
3. Update test result evaluation
4. Redeploy stack to apply changes

### Custom Test Scenarios
- Database connectivity tests
- External API validation
- Security compliance checks
- Load testing scenarios

### Integration with External Tools
- Call external monitoring systems
- Integrate with APM tools
- Trigger additional validation pipelines
- Send notifications to teams

## Troubleshooting

### Common Issues

**Integration tests not triggered**
- Check CodeDeploy deployment group configuration
- Verify Lambda function exists and has correct permissions
- Ensure appspec.yml includes correct hook configuration

**Tests fail unexpectedly**
- Check ALB test listener is correctly configured
- Verify target group health
- Review Lambda function logs for detailed errors
- Confirm network connectivity between Lambda and ALB

**Rollbacks not occurring**
- Verify auto-rollback configuration in deployment group
- Check Lambda function properly reports failure status
- Ensure CodeDeploy has necessary permissions

### Debug Steps
1. Run `./scripts/validate-setup.sh` for overall health
2. Check CloudWatch logs for detailed execution information
3. Verify ALB and target group configurations
4. Review CodeDeploy deployment events and logs

## Real-World Applications

This integration testing pattern is suitable for:

- **Microservices deployments** - Validate service-to-service communication
- **API deployments** - Test endpoint functionality and performance
- **Web applications** - Validate UI functionality and load times
- **Database migrations** - Test schema changes and data integrity
- **Configuration updates** - Validate application behavior with new configs

The demo provides a foundation that can be extended for production use cases with more sophisticated testing requirements.
