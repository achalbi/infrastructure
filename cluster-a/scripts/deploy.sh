#!/bin/bash

# Deployment script for infrastructure and applications
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    command -v terraform >/dev/null 2>&1 || { print_error "terraform is required but not installed. Aborting." >&2; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed. Aborting." >&2; exit 1; }
    command -v helm >/dev/null 2>&1 || { print_error "helm is required but not installed. Aborting." >&2; exit 1; }
    command -v helmfile >/dev/null 2>&1 || { print_error "helmfile is required but not installed. Aborting." >&2; exit 1; }
    
    print_status "All prerequisites are installed."
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    print_status "Deploying infrastructure with Terraform..."
    
    cd terraform
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init
    
    # Plan Terraform
    print_status "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    # Apply Terraform
    print_status "Applying Terraform configuration..."
    terraform apply tfplan
    
    # Get cluster credentials
    print_status "Getting EKS cluster credentials..."
    aws eks update-kubeconfig --region $(terraform output -raw aws_region) --name $(terraform output -raw cluster_name)
    
    cd ..
    print_status "Infrastructure deployment completed."
}

# Deploy ArgoCD
deploy_argocd() {
    print_status "Deploying ArgoCD..."
    
    # Create ArgoCD namespace and install
    kubectl apply -f argocd/manifests/namespace.yaml
    kubectl apply -f argocd/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    print_status "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n argocd
    
    # Deploy ArgoCD applications
    print_status "Deploying ArgoCD applications..."
    kubectl apply -f argocd/applications/
    
    print_status "ArgoCD deployment completed."
}

# Deploy applications with Helmfile
deploy_applications() {
    print_status "Deploying applications with Helmfile..."
    
    cd helmfile
    
    # Add repositories
    print_status "Adding Helm repositories..."
    helmfile repos
    
    # Deploy applications
    print_status "Deploying applications..."
    helmfile apply
    
    cd ..
    print_status "Application deployment completed."
}

# Main deployment function
main() {
    local environment=${1:-development}
    
    print_status "Starting deployment for environment: $environment"
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Deploy ArgoCD
    deploy_argocd
    
    # Deploy applications
    deploy_applications
    
    print_status "Deployment completed successfully!"
    
    # Display useful information
    print_status "Useful commands:"
    echo "  kubectl get pods -n argocd"
    echo "  kubectl port-forward svc/argocd-server 8080:80 -n argocd"
    echo "  helmfile status -f helmfile/helmfile.yaml"
}

# Run main function with all arguments
main "$@" 