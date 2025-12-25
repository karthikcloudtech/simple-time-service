# GitLab Runner Setup on AWS EC2

This guide explains how to set up a GitLab Runner on AWS EC2 to avoid using shared runner compute minutes.

## Prerequisites

- AWS account with EC2 access
- GitLab project with CI/CD enabled

## Step 1: Launch EC2 Instance

### Recommended Instance Type:
- **Instance Type**: `t3.medium` or `t3.large` (2-4 vCPU, 4-8 GB RAM)
- **OS**: Ubuntu 22.04 LTS or Amazon Linux 2023
- **Storage**: 20-30 GB (for Docker images and build artifacts)
- **Security Group**: 
  - Allow SSH (port 22) from your IP
  - No need to open ports for GitLab Runner (it connects outbound)

### Launch Steps:

1. Go to AWS Console → EC2 → Launch Instance
2. Choose **Ubuntu Server 22.04 LTS** (or Amazon Linux 2023)
3. Select instance type: **t3.medium** (or larger)
4. Configure security group (SSH access)
5. Launch instance with your key pair
6. Note the **Public IP** or **Public DNS**

## Step 2: Connect to EC2 Instance

```bash
# Replace with your key and instance details
ssh -i your-key.pem ubuntu@<EC2-PUBLIC-IP>

# For Amazon Linux, user is 'ec2-user' instead of 'ubuntu'
ssh -i your-key.pem ec2-user@<EC2-PUBLIC-IP>
```

## Step 3: Run Setup Script

```bash
# Download the setup script (or copy it to the instance)
curl -O https://raw.githubusercontent.com/your-repo/simple-time-service/main/scripts/setup-gitlab-runner-ec2.sh

# Or if you have the file locally, copy it:
# scp -i your-key.pem scripts/setup-gitlab-runner-ec2.sh ubuntu@<EC2-PUBLIC-IP>:~

# Make it executable
chmod +x setup-gitlab-runner-ec2.sh

# Run with sudo
sudo ./setup-gitlab-runner-ec2.sh
```

The script installs:
- Docker (for running CI/CD jobs)
- GitLab Runner
- AWS CLI
- kubectl
- helm
- Terraform

## Step 4: Register GitLab Runner

1. **Get Registration Token**:
   - Go to your GitLab project
   - Navigate to: **Settings → CI/CD → Runners**
   - Expand **"New instance runner"** section
   - Copy the **registration token**

2. **Register the Runner**:
   ```bash
   sudo gitlab-runner register
   ```

3. **Answer the prompts**:
   ```
   GitLab instance URL: https://gitlab.com/
   Registration token: <paste your token>
   Description: simple-time-service-ec2-runner
   Tags: project-specific
   Executor: docker
   Default Docker image: docker:latest
   ```

## Step 5: Start and Verify Runner

```bash
# Start GitLab Runner service
sudo gitlab-runner start

# Check status
sudo gitlab-runner status

# View logs (if needed)
sudo gitlab-runner --debug run
```

## Step 6: Verify in GitLab

1. Go to **Settings → CI/CD → Runners**
2. You should see your runner listed under **"Available specific runners"**
3. Status should be **online** (green circle)
4. It should have the tag: `project-specific`

## Step 7: Test Pipeline

Your CI/CD pipeline will now automatically use this runner instead of shared runners!

## Cost Optimization Tips

1. **Use Spot Instances**: Can reduce costs by up to 90%
2. **Auto Start/Stop**: Use AWS Lambda to start/stop instance based on schedule
3. **Reserved Instances**: If running 24/7, use Reserved Instances
4. **Right-size**: Start with t3.medium, adjust based on actual usage

### Estimated Costs:
- **t3.medium on-demand**: ~$30/month if running 24/7
- **t3.medium spot**: ~$3-9/month (much cheaper!)
- **t3.small on-demand**: ~$15/month (lighter workloads)

## Troubleshooting

### Runner not appearing in GitLab:
- Check runner status: `sudo gitlab-runner status`
- Check logs: `sudo gitlab-runner --debug run`
- Verify network connectivity from EC2 to GitLab

### Jobs stuck in "pending":
- Verify runner has the correct tag (`project-specific`)
- Check if runner is online in GitLab UI
- Verify Docker is running: `sudo systemctl status docker`

### Docker permission errors:
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and log back in
```

### Runner keeps stopping:
```bash
# Install as systemd service (persistent)
sudo gitlab-runner install
sudo gitlab-runner start
sudo systemctl enable gitlab-runner
```

## Security Best Practices

1. **Use IAM Roles**: Attach IAM role to EC2 instance for AWS API access (instead of access keys)
2. **Restrict Security Group**: Only allow SSH from your IP
3. **Regular Updates**: Keep instance and packages updated
4. **Use Private Subnet**: For production, consider placing runner in private subnet
5. **Monitor Costs**: Set up CloudWatch alarms for unexpected costs

## Optional: Auto-Scale with ECS/EKS

For high-volume workloads, consider:
- **ECS**: Run GitLab Runner on ECS Fargate (serverless)
- **EKS**: Run GitLab Runner as Kubernetes deployment
- **GitLab Runner Autoscaler**: Auto-scale runners based on job queue

## Next Steps

Once your runner is registered and online:
1. Your pipelines will automatically use it
2. You'll stop using shared runner compute minutes
3. Monitor EC2 instance costs and performance
4. Consider setting up auto-scaling if needed

