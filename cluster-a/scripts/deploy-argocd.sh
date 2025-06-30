#!/bin/bash

# ArgoCD Deployment Script
# This script deploys ArgoCD using Helmfile and manages the GitOps workflow

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

# Check if kubectl is available
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v helmfile &> /dev/null; then
        print_error "helmfile is not installed or not in PATH"
        exit 1
    fi
    
    print_status "Prerequisites check passed"
}

# Deploy ArgoCD using Helmfile
deploy_argocd() {
    print_status "Deploying ArgoCD using Helmfile..."
    
    cd "$(dirname "$0")/../helmfile"
    
    # Deploy ArgoCD
    helmfile apply --selector name=argocd
    
    print_status "ArgoCD deployment completed"
}

# Wait for ArgoCD to be ready
wait_for_argocd() {
    print_status "Waiting for ArgoCD to be ready..."
    
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    
    print_status "ArgoCD is ready"
}

# Get ArgoCD admin password
get_admin_password() {
    print_status "Getting ArgoCD admin password..."
    
    # Get the admin password from the secret
    ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    echo "=========================================="
    echo "ArgoCD Admin Password: $ADMIN_PASSWORD"
    echo "=========================================="
    print_warning "Please save this password securely"
}

# Port forward ArgoCD server
port_forward() {
    print_status "Setting up port forward for ArgoCD server..."
    print_status "ArgoCD UI will be available at: http://localhost:8080"
    print_status "Username: admin"
    print_status "Press Ctrl+C to stop port forwarding"
    
    kubectl port-forward svc/argocd-server -n argocd 8080:443
}

# Deploy ArgoCD applications
deploy_applications() {
    print_status "Deploying ArgoCD applications..."
    
    cd "$(dirname "$0")/../argocd/applications"
    
    # Apply all ArgoCD applications
    kubectl apply -f .
    
    print_status "ArgoCD applications deployed"
}

# Main function
main() {
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            deploy_argocd
            wait_for_argocd
            get_admin_password
            deploy_applications
            print_status "ArgoCD deployment completed successfully!"
            print_status "You can now access ArgoCD UI or run: $0 port-forward"
            ;;
        "port-forward")
            port_forward
            ;;
        "applications")
            deploy_applications
            ;;
        "password")
            get_admin_password
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  deploy        Deploy ArgoCD and applications (default)"
            echo "  port-forward  Start port forward to ArgoCD UI"
            echo "  applications  Deploy only ArgoCD applications"
            echo "  password      Get ArgoCD admin password"
            echo "  help          Show this help message"
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 