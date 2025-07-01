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
    
    # Deploy core infrastructure first (ArgoCD, cert-manager, etc.)
    print_status "Deploying core infrastructure..."
    helmfile apply --selector name=argocd
    helmfile apply --selector name=cert-manager
    helmfile apply --selector name=ingress-nginx
    
    # Wait for cert-manager to be ready
    print_status "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
    
    # Deploy OpenTelemetry components
    print_status "Deploying OpenTelemetry components..."
    helmfile apply --selector name=opentelemetry-collector
    helmfile apply --selector name=opentelemetry-operator
    
    # Wait for OpenTelemetry to be ready
    print_status "Waiting for OpenTelemetry to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-collector -n observability || true
    kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-operator-controller-manager -n observability || true
    
    # Deploy pre-install charts first (OpenTelemetry instrumentation)
    print_status "Deploying pre-install charts (OpenTelemetry instrumentation)..."
    helmfile apply --selector name=pre-install
    
    # Wait for pre-install resources to be ready
    print_status "Waiting for pre-install resources to be ready..."
    sleep 10  # Give time for OpenTelemetry instrumentation to be created
    
    # Deploy appender-java applications
    print_status "Deploying appender-java applications..."
    helmfile apply --selector name=appender-java
    
    # Deploy all remaining applications
    print_status "Deploying remaining applications..."
    helmfile apply
    
    cd ..
    print_status "Application deployment completed."
}

# Deploy environment-specific applications
deploy_environment() {
    local environment=${1:-development}
    
    print_status "Deploying $environment environment..."
    
    cd helmfile/environments/$environment
    
    # Deploy pre-install chart first (OpenTelemetry instrumentation)
    print_status "Deploying pre-install chart for $environment (OpenTelemetry instrumentation)..."
    helmfile apply --selector name=pre-install-$environment
    
    # Wait for pre-install to be ready
    print_status "Waiting for pre-install resources to be ready..."
    sleep 10
    
    # Deploy appender-java application
    print_status "Deploying appender-java for $environment..."
    helmfile apply --selector name=appender-java-$environment
    
    # Deploy all environment applications
    print_status "Deploying all $environment applications..."
    helmfile apply
    
    cd ../../..
    print_status "$environment environment deployment completed."
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
    
    # Deploy environment-specific applications
    deploy_environment $environment
    
    print_status "Deployment completed successfully!"
    
    # Display useful information
    print_status "Useful commands:"
    echo "  kubectl get pods -n argocd"
    echo "  kubectl port-forward svc/argocd-server 8080:80 -n argocd"
    echo "  helmfile status -f helmfile/helmfile.yaml"
    echo "  helmfile status -f helmfile/environments/$environment/helmfile.yaml"
    
    # Display application status
    print_status "Application Status:"
    echo "  kubectl get pods -n appender-java-$environment"
    echo "  kubectl get configmaps -n appender-java-$environment"
    echo "  kubectl get secrets -n appender-java-$environment"
}

# Run main function with all arguments
main "$@" 