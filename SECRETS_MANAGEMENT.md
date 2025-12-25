# Secrets Management

This project uses **GitLab CI/CD Variables** as the primary source for secrets management.

## Primary: GitLab CI/CD Variables

All secrets are stored in GitLab CI/CD Variables and are automatically available during CI/CD pipeline execution.

### Configuration

Configure secrets in GitLab: **Settings → CI/CD → Variables**

### Required Variables

| Variable | Description | Required | Protected | Masked |
|----------|-------------|----------|-----------|--------|
| `AWS_ACCESS_KEY_ID` | AWS access key for CI/CD operations | Yes | Yes | No |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key | Yes | Yes | Yes |
| `AWS_DEFAULT_REGION` | AWS region for deployments | Yes | No | No |
| `DOCKERHUB_USERNAME` | Docker Hub username | Yes | Yes | No |
| `DOCKERHUB_TOKEN` | Docker Hub access token | Yes | Yes | Yes |

### Using Variables in CI/CD

Variables are automatically available as environment variables in GitLab CI/CD jobs:

```yaml
script:
  - echo "Using AWS credentials from GitLab variables"
  - aws s3 ls  # Uses AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
```

### Best Practices

1. **Mark sensitive variables as "Masked"** - Prevents them from appearing in job logs
2. **Mark production variables as "Protected"** - Only available in protected branches/tags
3. **Use environment-specific variables** - Create separate variables for dev/staging/prod
4. **Rotate secrets regularly** - Update variables periodically

## Application Secrets

For application runtime secrets (not CI/CD secrets), you can:

1. **Use Kubernetes Secrets** - Created manually or via ArgoCD
2. **Use GitLab CI/CD Variables** - Passed to Kubernetes during deployment
3. **Use External Secrets Operator** - Sync from AWS Secrets Manager or other sources (if configured)

### Example: Creating Kubernetes Secret from GitLab Variable

```bash
# In GitLab CI/CD job
kubectl create secret generic app-secrets \
  --from-literal=api-key="$API_KEY" \
  --from-literal=db-password="$DB_PASSWORD" \
  -n simple-time-service \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Security Notes

- ✅ Never commit secrets to Git
- ✅ Use GitLab CI/CD Variables for all CI/CD secrets
- ✅ Mark sensitive variables as "Masked" and "Protected"
- ✅ Use separate variables for different environments
- ✅ Rotate secrets regularly
- ❌ Don't hardcode secrets in code or configuration files
- ❌ Don't log secret values

