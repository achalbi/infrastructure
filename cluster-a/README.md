# Infrastructure Repository

This repository contains the infrastructure as code (IaC) for deploying applications using modern DevOps practices.

## Repository Structure

```
├── argocd/                 # ArgoCD configuration and manifests
├── helmfile/              # Helmfile configurations for app deployments
├── terraform/             # Terraform configurations for infrastructure
├── scripts/               # Shell scripts for automation
├── docs/                  # Documentation
└── examples/              # Example configurations
```

## Prerequisites

- Kubernetes cluster
- ArgoCD installed
- Terraform >= 1.0
- Helm >= 3.0
- kubectl configured

## Quick Start

1. **Initialize Terraform**:
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

2. **Deploy ArgoCD**:
   ```bash
   kubectl apply -f argocd/manifests/
   ```

3. **Deploy Applications**:
   ```bash
   cd helmfile
   helmfile apply
   ```

## Components

### ArgoCD
- Application definitions
- Project configurations
- RBAC settings
- Custom resources

### Helmfile
- Application deployment configurations
- Environment-specific values
- Dependency management
- Multi-environment support

### Terraform
- Infrastructure provisioning
- Cloud resources
- Network configuration
- Security groups and policies

### Scripts
- Deployment automation
- Environment setup
- Backup and restore
- Monitoring and health checks

## Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## License

MIT License 