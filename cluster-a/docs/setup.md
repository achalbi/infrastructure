# Infrastructure Setup Guide

This guide will help you set up and deploy the infrastructure using Terraform, ArgoCD, and Helmfile.

## Prerequisites

Before you begin, ensure you have the following tools installed:

### Required Tools

1. **Terraform** (>= 1.0)
   ```bash
   # Download from https://www.terraform.io/downloads.html
   # Or use package manager
   brew install terraform  # macOS
   ```

2. **kubectl** (>= 1.28)
   ```bash
   # Download from https://kubernetes.io/docs/tasks/tools/
   # Or use package manager
   brew install kubectl  # macOS
   ```

3. **Helm** (>= 3.0)
   ```bash
   # Download from https://helm.sh/docs/intro/install/
   # Or use package manager
   brew install helm  # macOS
   ```

4. **Helmfile** (>= 0.150.0)
   ```bash
   # Download from https://github.com/helmfile/helmfile/releases
   # Or use package manager
   brew install helmfile  # macOS
   ```

5. **AWS CLI** (>= 2.0)
   ```bash
   # Download from https://aws.amazon.com/cli/
   # Or use package manager
   brew install awscli  # macOS
   ```

### AWS Configuration

1. **Install AWS CLI** and configure your credentials:
   ```bash
   aws configure
   ```

2. **Set up AWS credentials** with appropriate permissions for:
   - EKS (Elastic Kubernetes Service)
   - VPC and networking
   - RDS (Relational Database Service)
   - IAM roles and policies

## Quick Start

### 1. Clone the Repository

```bash
git clone <your-repo-url>
cd infrastructure
```

### 2. Configure Variables

Create a `terraform.tfvars` file in the `terraform` directory:

```hcl
aws_region = "us-west-2"
environment = "development"
cluster_name = "my-cluster"
vpc_cidr = "10.0.0.0/16"
db_username = "admin"
db_password = "your-secure-password"
```

### 3. Deploy Infrastructure

Run the deployment script:

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

Or deploy manually:

```bash
# Deploy infrastructure
cd terraform
terraform init
terraform plan
terraform apply

# Deploy ArgoCD
kubectl apply -f argocd/manifests/
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Deploy applications
cd helmfile
helmfile apply
```

## Manual Setup Steps

### Step 1: Deploy Infrastructure with Terraform

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan

# Get cluster credentials
aws eks update-kubeconfig --region $(terraform output -raw aws_region) --name $(terraform output -raw cluster_name)
```

### Step 2: Deploy ArgoCD

```bash
# Create ArgoCD namespace
kubectl apply -f argocd/manifests/namespace.yaml

# Deploy ArgoCD
kubectl apply -f argocd/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n argocd

# Deploy ArgoCD applications
kubectl apply -f argocd/applications/
```

### Step 3: Deploy Applications with Helmfile

```bash
cd helmfile

# Add Helm repositories
helmfile repos

# Deploy applications
helmfile apply
```

## Accessing Services

### ArgoCD UI

```bash
# Port forward ArgoCD server
kubectl port-forward svc/argocd-server 8080:80 -n argocd

# Access at http://localhost:8080
# Default username: admin
# Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Sample Application

```bash
# Port forward sample application
kubectl port-forward svc/sample-app 8081:80 -n sample-app

# Access at http://localhost:8081
```

## Monitoring and Maintenance

### Health Checks

Run the monitoring script to check infrastructure health:

```bash
chmod +x scripts/monitoring.sh
./scripts/monitoring.sh
```

### Backups

Create backups of your infrastructure:

```bash
chmod +x scripts/backup.sh
./scripts/backup.sh
```

### Updates

To update applications:

```bash
cd helmfile
helmfile apply
```

To update infrastructure:

```bash
cd terraform
terraform plan
terraform apply
```

## Troubleshooting

### Common Issues

1. **Terraform state locked**
   ```bash
   terraform force-unlock <lock-id>
   ```

2. **ArgoCD sync issues**
   ```bash
   kubectl get applications -n argocd
   kubectl describe application <app-name> -n argocd
   ```

3. **Helmfile issues**
   ```bash
   helmfile list
   helmfile status
   ```

### Logs

Check logs for debugging:

```bash
# ArgoCD logs
kubectl logs -n argocd deployment/argocd-server
kubectl logs -n argocd deployment/argocd-application-controller

# Application logs
kubectl logs -n sample-app deployment/sample-app
```

## Security Considerations

1. **Use strong passwords** for database and ArgoCD
2. **Enable encryption** for RDS and EBS volumes
3. **Use IAM roles** instead of access keys
4. **Enable VPC flow logs** for network monitoring
5. **Regular security updates** for all components

## Cost Optimization

1. **Use appropriate instance types** for your workload
2. **Enable auto-scaling** for EKS node groups
3. **Use spot instances** for non-critical workloads
4. **Monitor resource usage** and adjust accordingly
5. **Clean up unused resources** regularly 