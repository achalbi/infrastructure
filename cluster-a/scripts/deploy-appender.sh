#!/bin/bash

# =============================================================================
# Appender Java Deployment Script for Bash
# =============================================================================
# This script deploys only the appender-java application using Helmfile
# 
# Features:
# - Environment-specific deployments (dev/prod)
# - Multiple instance management (3 for dev, 10 for prod)
# - Health checking and status monitoring
# - Chain testing for the appender instances
# - Safe deletion with confirmation
# - Interactive menu for easy selection
# - Targets kind-cluster-a cluster
#
# Usage: ./deploy-appender.sh [environment] [action]
# Example: ./deploy-appender.sh dev deploy
# =============================================================================

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

# Default values for command line arguments
# $1 = environment (dev/prod), defaults to "dev"
# $2 = action (deploy/status/test/delete/help), defaults to "deploy"
ENVIRONMENT=${1:-"dev"}
ACTION=${2:-"deploy"}

# Cluster configuration
CLUSTER_NAME="cluster-a"

# =============================================================================
# COLOR DEFINITIONS FOR OUTPUT
# =============================================================================
# These ANSI escape codes provide colored output for better readability
RED='\033[0;31m'      # Red for errors
GREEN='\033[0;32m'    # Green for success/info
YELLOW='\033[1;33m'   # Yellow for warnings
CYAN='\033[0;36m'     # Cyan for section headers
BLUE='\033[0;34m'     # Blue for menu options
NC='\033[0m'          # No Color (reset)

# =============================================================================
# UTILITY FUNCTIONS FOR OUTPUT
# =============================================================================

# Print status messages in green
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Print warning messages in yellow
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Print error messages in red
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Print menu headers in cyan
print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Print menu options in blue
print_option() {
    echo -e "${BLUE}$1${NC}"
}

# =============================================================================
# CLUSTER AND PREREQUISITE CHECKING
# =============================================================================

# Verify that required tools are installed and available in PATH
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helmfile is available
    if ! command -v helmfile &> /dev/null; then
        print_error "helmfile is not installed or not in PATH"
        exit 1
    fi
    
    print_status "Prerequisites check passed"
}

# Check if the target cluster exists and is accessible
check_cluster() {
    print_status "Checking cluster connectivity..."
    
    # Check if cluster exists
    if ! kind get clusters | grep -q "$CLUSTER_NAME"; then
        print_error "Cluster '$CLUSTER_NAME' not found. Available clusters:"
        kind get clusters
        exit 1
    fi
    
    # Check if kubectl can connect to the cluster
    if ! kubectl cluster-info --context "kind-$CLUSTER_NAME" &> /dev/null; then
        print_error "Cannot connect to cluster '$CLUSTER_NAME'. Please check your kubeconfig."
        exit 1
    fi
    
    print_status "Connected to cluster: $CLUSTER_NAME"
}

# Set the correct kubectl context
set_cluster_context() {
    print_status "Setting kubectl context to kind-$CLUSTER_NAME..."
    kubectl config use-context "kind-$CLUSTER_NAME"
}

# =============================================================================
# INTERACTIVE MENU SYSTEM
# =============================================================================

# Display the main environment selection menu
show_main_menu() {
    clear
    print_header "=========================================="
    print_header "    Appender Java Deployment Manager"
    print_header "=========================================="
    echo ""
    print_header "Target Cluster: $CLUSTER_NAME"
    echo ""
    print_header "Select Environment:"
    print_option "1) Development (4 instances)"
    print_option "2) Production (10 instances)"
    print_option "3) Infrastructure"
    echo ""
    print_option "4) Help"
    print_option "5) Exit"
    echo ""
}

# Display the action menu for a selected environment
show_action_menu() {
    local env=$1
    clear
    print_header "=========================================="
    print_header "    Appender Java Deployment Manager"
    print_header "=========================================="
    echo ""
    print_header "Target Cluster: $CLUSTER_NAME"
    print_header "Environment: $env"
    echo ""
    
    if [ "$env" = "infra" ]; then
        print_header "Infrastructure Actions:"
        print_option "1) Deploy Infrastructure (ArgoCD, Ingress-Nginx, cert-manager, OpenTelemetry Operator, OpenTelemetry Collector)"
        print_option "2) Show Infrastructure Status"
        print_option "3) Back to Environment Selection"
        echo ""
    else
        print_header "Appender Actions:"
        print_option "1) Deploy Appender"
        print_option "2) Show Status"
        print_option "3) Test Chain"
        print_option "4) Delete Appender"
        print_option "5) Restart Appender Pods"
        print_option "6) Port Forward to First Appender"
        print_option "7) Back to Environment Selection"
        echo ""
    fi
    
}

# Get environment selection from user
get_environment_selection() {
    local choice
    read -p "Enter your choice (1-5): " choice
    
    case $choice in
        1) echo "dev" ;;
        2) echo "prod" ;;
        3) echo "infra" ;;
        4) echo "help" ;;
        5) echo "exit" ;;
        *) 
            print_error "Invalid choice"
            return 1
            ;;
    esac
}

# Get action selection from user
get_action_selection() {
    local env=$1
    local choice
    
    if [ "$env" = "infra" ]; then
        read -p "Enter your choice (1-3): " choice
        case $choice in
            1) echo "infra" ;;
            2) echo "status" ;;
            3) echo "back" ;;
            *) 
                print_error "Invalid choice"
                return 1
                ;;
        esac
    else
        read -p "Enter your choice (1-7): " choice
        case $choice in
            1) echo "deploy" ;;
            2) echo "status" ;;
            3) echo "test" ;;
            4) echo "delete" ;;
            5) echo "restart" ;;
            6) echo "portforward" ;;
            7) echo "back" ;;
            *) 
                print_error "Invalid choice"
                return 1
                ;;
        esac
    fi
}

# Interactive mode - show menu and handle user input
interactive_mode() {
    while true; do
        show_main_menu
        
        # Get environment selection
        ENVIRONMENT=$(get_environment_selection)
        if [ $? -ne 0 ]; then
            sleep 2
            continue
        fi
        
        # Handle exit
        if [ "$ENVIRONMENT" = "exit" ]; then
            print_status "Exiting..."
            exit 0
        fi
        
        # Handle help
        if [ "$ENVIRONMENT" = "help" ]; then
            show_help
            echo ""
            read -p "Press Enter to continue..."
            continue
        fi
        
        # Show action menu for selected environment
        while true; do
            show_action_menu "$ENVIRONMENT"
            
            # Get action selection
            ACTION=$(get_action_selection "$ENVIRONMENT")
            if [ $? -ne 0 ]; then
                sleep 2
                continue
            fi
            
            # Handle back to main menu
            if [ "$ACTION" = "back" ]; then
                break
            fi
            
            # Execute the selected action
            echo ""
            print_status "Executing: $ACTION on $ENVIRONMENT environment"
            echo ""
            
            # Run the main logic
            execute_action "$ENVIRONMENT" "$ACTION"
            
            echo ""
            read -p "Press Enter to continue..."
        done
    done
}

# =============================================================================
# ENVIRONMENT CONFIGURATION
# =============================================================================

# Map environment names to Kubernetes namespaces
get_namespace() {
    local env=$1
    case ${env,,} in  # ${env,,} converts to lowercase
        "dev") echo "appender-java-dev" ;;
        "prod") echo "appender-java-prod" ;;
        *) 
            print_error "Invalid environment: $env. Use 'dev' or 'prod'"
            exit 1
            ;;
    esac
}

# Get the number of instances to deploy based on environment
get_instance_count() {
    local env=$1
    case ${env,,} in
        "dev") echo 4 ;;   # Development: 4 instances
        "prod") echo 10 ;; # Production: 10 instances
        *) echo 4 ;;       # Default to 4
    esac
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

# Deploy infrastructure components (ArgoCD, Ingress-Nginx, cert-manager, OpenTelemetry Operator)
deploy_infrastructure() {
    print_status "Deploying infrastructure components to cluster: $CLUSTER_NAME"
    echo ""
    script_dir=$(cd "$(dirname "$0")" && pwd)
    cd "$script_dir/../helmfile"

    # Deploy ArgoCD
    print_status "Deploying ArgoCD..."
    helmfile apply --selector name=argocd
    # Wait for ArgoCD
    print_status "Waiting for ArgoCD..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || print_error "ArgoCD failed to become ready"

    # Deploy Ingress-Nginx
    print_status "Deploying Ingress-Nginx..."
    helmfile apply --selector name=ingress-nginx
    # Wait for Ingress-Nginx
    print_status "Waiting for Ingress-Nginx..."
    kubectl wait --for=condition=available --timeout=300s deployment/ingress-nginx-controller -n ingress-nginx || print_error "Ingress-Nginx failed to become ready"

    # Deploy cert-manager
    print_status "Deploying cert-manager..."
    helmfile apply --selector name=cert-manager
    # Wait for cert-manager
    print_status "Waiting for cert-manager..."
    kubectl get namespace cert-manager >/dev/null 2>&1 || kubectl create namespace cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager || print_error "cert-manager failed to become ready"

    # Deploy OpenTelemetry Operator
    print_status "Deploying OpenTelemetry Operator..."
    helmfile apply --selector name=opentelemetry-operator
    # Wait for OpenTelemetry Operator
    print_status "Waiting for OpenTelemetry Operator..."
    kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-operator -n observability || print_error "OpenTelemetry Operator failed to become ready"

    # Deploy OpenTelemetry Collector
    print_status "Deploying OpenTelemetry Collector..."
    helmfile apply --selector name=opentelemetry-collector
    # Wait for OpenTelemetry Collector
    print_status "Waiting for OpenTelemetry Collector..."
    kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-collector -n observability || print_error "OpenTelemetry Collector failed to become ready"

    print_status "All infrastructure components deployed and ready"
}

# Wait for infrastructure components to be ready
wait_for_infrastructure() {
    print_status "Waiting for infrastructure components to be ready..."
    
    # Wait for ArgoCD
    print_status "Waiting for ArgoCD..."
    if kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd; then
        print_status "ArgoCD is ready"
    else
        print_error "ArgoCD failed to become ready"
    fi
    
    # Wait for Ingress-Nginx
    print_status "Waiting for Ingress-Nginx..."
    if kubectl wait --for=condition=available --timeout=300s deployment/ingress-nginx-controller -n ingress-nginx; then
        print_status "Ingress-Nginx is ready"
    else
        print_error "Ingress-Nginx failed to become ready"
    fi
    
    # Wait for cert-manager
    print_status "Waiting for cert-manager..."
    if kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager; then
        print_status "cert-manager is ready"
    else
        print_error "cert-manager failed to become ready"
    fi
    
    # Wait for OpenTelemetry Operator
    print_status "Waiting for OpenTelemetry Operator..."
    if kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-operator -n observability; then
        print_status "OpenTelemetry Operator is ready"
    else
        print_error "OpenTelemetry Operator failed to become ready"
    fi
    
    # Wait for OpenTelemetry Collector
    print_status "Waiting for OpenTelemetry Collector..."
    if kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-collector -n observability; then
        print_status "OpenTelemetry Collector is ready"
    else
        print_error "OpenTelemetry Collector failed to become ready"
    fi
    
    print_status "All infrastructure components are ready"
}

# Show infrastructure status
show_infrastructure_status() {
    print_status "Checking infrastructure status for cluster: $CLUSTER_NAME"
    echo ""
    
    # Show ArgoCD status
    echo -e "${CYAN}=== ArgoCD Status ===${NC}"
    kubectl get deployments -n argocd
    echo ""
    kubectl get services -n argocd
    echo ""
    kubectl get pods -n argocd
    
    echo ""
    echo -e "${CYAN}=== Ingress-Nginx Status ===${NC}"
    kubectl get deployments -n ingress-nginx
    echo ""
    kubectl get services -n ingress-nginx
    echo ""
    kubectl get pods -n ingress-nginx
    
    echo ""
    echo -e "${CYAN}=== cert-manager Status ===${NC}"
    kubectl get deployments -n cert-manager
    echo ""
    kubectl get services -n cert-manager
    echo ""
    kubectl get pods -n cert-manager
    
    echo ""
    echo -e "${CYAN}=== OpenTelemetry Operator Status ===${NC}"
    kubectl get deployments -n observability
    echo ""
    kubectl get services -n observability
    echo ""
    kubectl get pods -n observability

    echo ""
    echo -e "${CYAN}=== OpenTelemetry Collector Status ===${NC}"
    kubectl get deployments -n observability | grep opentelemetry-collector || true
    kubectl get services -n observability | grep opentelemetry-collector || true
    kubectl get pods -n observability | grep opentelemetry-collector || true
}

# Main deployment function that orchestrates the appender-java deployment
deploy_appender() {
    local env=$1
    local namespace=$(get_namespace "$env")
    local instance_count=$(get_instance_count "$env")
    
    # Display deployment information
    print_status "Deploying appender-java to $env environment"
    print_status "Cluster: $CLUSTER_NAME"
    print_status "Namespace: $namespace"
    print_status "Instance count: $instance_count"
    echo ""
    
    # Navigate to the helmfile directory (robust, works from any directory)
    script_dir=$(cd "$(dirname "$0")" && pwd)
    echo "SCRIPT DIR: $script_dir"
    echo "CD TO: $script_dir/../helmfile"
    cd "$script_dir/../helmfile"
    
    # Deploy using environment-specific helmfile configuration
    case $env in
        "dev")
            print_status "Using development environment configuration..."
            # Deploy using the development environment helmfile
            helmfile -f environments/development/helmfile.yaml apply --selector name=appender-java-dev
            ;;
        "prod")
            print_status "Using production environment configuration..."
            # Deploy using the production environment helmfile
            helmfile -f environments/production/helmfile.yaml apply --selector name=appender-java-prod
            ;;
    esac
    
    print_status "Appender-java deployment completed"
    port_forward_and_open "$env"
}

# =============================================================================
# MONITORING AND STATUS FUNCTIONS
# =============================================================================

# Wait for all appender-java instances to become ready
wait_for_appender() {
    local env=$1
    local namespace=$(get_namespace "$env")
    local instance_count=$(get_instance_count "$env")
    
    print_status "Waiting for appender-java instances to be ready in $env environment..."
    
    # Loop through each instance and wait for it to be ready
    for ((i=1; i<=instance_count; i++)); do
        instance_name=$(printf "appender-java-%02d" $i)  # Format: appender-java-01, 02, etc.
        print_status "Waiting for $instance_name..."
        
        # Wait for deployment to be available (ready state)
        if kubectl wait --for=condition=available --timeout=300s deployment/$instance_name -n $namespace; then
            print_status "$instance_name is ready"
        else
            print_error "$instance_name failed to become ready"
        fi
    done
    
    print_status "All appender-java instances are ready"
}

# Display comprehensive status of all appender-java resources
show_status() {
    local env=$1
    local namespace=$(get_namespace "$env")
    local instance_count=$(get_instance_count "$env")
    
    print_status "Checking status for appender-java in $env environment"
    print_status "Cluster: $CLUSTER_NAME"
    print_status "Namespace: $namespace"
    echo ""
    
    # Show all deployments
    echo -e "${CYAN}=== Deployments ===${NC}"
    kubectl get deployments -n "$namespace" --selector=app.kubernetes.io/name=appender-java
    
    # Show all services
    echo ""
    echo -e "${CYAN}=== Services ===${NC}"
    kubectl get services -n "$namespace" --selector=app.kubernetes.io/name=appender-java
    
    # Show all pods
    echo ""
    echo -e "${CYAN}=== Pods ===${NC}"
    kubectl get pods -n "$namespace" --selector=app.kubernetes.io/name=appender-java
    
    # Show detailed instance information including NODE_TYPE
    echo ""
    echo -e "${CYAN}=== Instance Details ===${NC}"
    for ((i=1; i<=instance_count; i++)); do
        instance_name=$(printf "appender-java-%02d" $i)
        
        # Get the pod name for this instance
        pod_name=$(kubectl get pods -n "$namespace" --selector="app.kubernetes.io/instance=$instance_name" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
        
        if [ -n "$pod_name" ]; then
            # Extract status information from the pod
            status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath="{.status.phase}")
            ready=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath="{.status.containerStatuses[0].ready}")
            node_type=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath="{.spec.containers[0].env[?(@.name=='NODE_TYPE')].value}")
            
            # Color-code based on readiness
            if [ "$ready" = "true" ]; then
                echo -e "${GREEN}$instance_name : $status (Ready: $ready, Type: $node_type)${NC}"
            else
                echo -e "${RED}$instance_name : $status (Ready: $ready, Type: $node_type)${NC}"
            fi
        else
            echo -e "${RED}$instance_name : Not found${NC}"
        fi
    done
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Safely delete all appender-java instances with confirmation
remove_appender() {
    local env=$1
    local namespace=$(get_namespace "$env")
    
    # Warn user and get confirmation
    print_warning "This will delete all appender-java instances in $env environment"
    print_warning "Cluster: $CLUSTER_NAME"
    read -p "Are you sure you want to continue? (y/N): " confirmation
    
    # Only proceed if user confirms with 'y' or 'Y'
    if [[ $confirmation =~ ^[Yy]$ ]]; then
        print_status "Deleting appender-java from $env environment..."
        
        # Navigate to helmfile directory (robust, works from any directory)
        script_dir=$(cd "$(dirname "$0")" && pwd)
        echo "SCRIPT DIR: $script_dir"
        echo "CD TO: $script_dir/../helmfile"
        cd "$script_dir/../helmfile"
        
        # Delete using environment-specific helmfile
        case $env in
            "dev")
                helmfile -f environments/development/helmfile.yaml delete --selector name=appender-java-dev
                ;;
            "prod")
                helmfile -f environments/production/helmfile.yaml delete --selector name=appender-java-prod
                ;;
        esac
        
        print_status "Appender-java deletion completed"
    else
        print_status "Deletion cancelled"
    fi
}

# Restart all appender-java pods in the selected environment
restart_appender_pods() {
    local env=$1
    local namespace=$(get_namespace "$env")
    local instance_count=$(get_instance_count "$env")
    print_status "Restarting all appender-java pods in $env environment (namespace: $namespace)..."
    for ((i=1; i<=instance_count; i++)); do
        instance_name=$(printf "appender-java-%02d" $i)
        print_status "Restarting pod for $instance_name..."
        kubectl rollout restart deployment/$instance_name -n $namespace
    done
    print_status "All appender-java pods have been restarted."
    port_forward_and_open "$env"
}

# Utility function to open a URL in the default browser (cross-platform)
open_url() {
    local url="$1"
    if command -v xdg-open > /dev/null; then
        xdg-open "$url"
    elif command -v open > /dev/null; then
        open "$url"
    elif command -v start > /dev/null; then
        start "$url"
    else
        print_warning "Could not detect the web browser to open $url. Please open it manually."
    fi
}

# Port-forward the first appender-java service and open the URL
port_forward_and_open() {
    local env=$1
    local namespace=$(get_namespace "$env")
    local base_name="appender-java-01"
    local port=8080
    # Try common service name patterns
    local service_name=""
    for candidate in "$base_name-service" "$base_name"; do
        if kubectl get svc "$candidate" -n "$namespace" &>/dev/null; then
            service_name="$candidate"
            break
        fi
    done
    if [ -z "$service_name" ]; then
        print_error "Could not find a service for $base_name in namespace $namespace."
        print_status "Available services:"
        kubectl get svc -n "$namespace"
        return 1
    fi
    print_status "Port-forwarding $service_name in namespace $namespace to localhost:$port..."
    kubectl port-forward service/$service_name $port:$port -n $namespace >/dev/null 2>&1 &
    local pf_pid=$!
    sleep 2
    # Check if port-forward is running
    if ! ps -p $pf_pid > /dev/null; then
        print_error "Port-forward process failed to start. Check if the service and port are correct."
        print_status "Try running: kubectl port-forward service/$service_name $port:$port -n $namespace"
        return 1
    fi
    local url="http://localhost:$port"
    print_status "Opening $url in your browser..."
    open_url "$url"
    read -p "Press Enter to stop port-forwarding..."
    kill $pf_pid 2>/dev/null
}

# =============================================================================
# TESTING FUNCTIONS
# =============================================================================

# Test the health of all instances in the chain
test_chain() {
    local env=$1
    local namespace=$(get_namespace "$env")
    local instance_count=$(get_instance_count "$env")
    
    print_status "Testing appender-java chain in $env environment"
    print_status "Cluster: $CLUSTER_NAME"
    echo ""
    
    # Test each instance's health endpoint
    for ((i=1; i<=instance_count; i++)); do
        instance_name=$(printf "appender-java-%02d" $i)
        service_name="$instance_name-service"
        
        echo -n "Testing $instance_name..."
        
        # Check if the service exists
        if kubectl get service "$service_name" -n "$namespace" >/dev/null 2>&1; then
            # Get the service port
            port=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath="{.spec.ports[0].port}")
            
            # Set up port-forward to access the service locally
            kubectl port-forward service/"$service_name" "$port:$port" -n "$namespace" >/dev/null 2>&1 &
            port_forward_pid=$!
            
            # Wait for port-forward to establish
            sleep 2
            
            # Test the health endpoint
            if curl -s -f "http://localhost:$port/actuator/health" >/dev/null 2>&1; then
                echo -e " ${GREEN}HEALTHY${NC}"
            else
                echo -e " ${RED}UNHEALTHY${NC}"
            fi
            
            # Clean up port-forward process
            kill $port_forward_pid 2>/dev/null
            wait $port_forward_pid 2>/dev/null
        else
            echo -e " ${RED}Service not found${NC}"
        fi
    done
}

# =============================================================================
# HELP AND DOCUMENTATION
# =============================================================================

# Display usage information and examples
show_help() {
    echo "Usage: $0 [environment] [action]"
    echo ""
    echo "Environments:"
    echo "  dev              Development environment (4 instances)"
    echo "  prod             Production environment (10 instances)"
    echo "  infra            Infrastructure components (ArgoCD, Ingress-Nginx)"
    echo ""
    echo "Actions:"
    echo "  infra            Deploy infrastructure components"
    echo "  deploy           Deploy appender-java (default)"
    echo "  status           Show deployment status"
    echo "  test             Test the instance chain"
    echo "  delete           Delete appender-java deployment"
    echo "  restart          Restart all appender-java pods in the environment"
    echo "  help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 infra         # Deploy infrastructure"
    echo "  $0 dev deploy    # Deploy appender-java to dev"
    echo "  $0 prod status   # Show production status"
    echo "  $0 dev test      # Test dev instance chain"
    echo "  $0 prod delete   # Delete production deployment"
    echo "  $0 dev restart   # Restart all dev appender-java pods"
    echo "  $0 prod restart  # Restart all prod appender-java pods"
    echo ""
    echo "Interactive Mode:"
    echo "  $0               Run without arguments for interactive menu"
    echo ""
    echo "Cluster Information:"
    echo "  Target Cluster: $CLUSTER_NAME"
    echo "  Context: kind-$CLUSTER_NAME"
    echo ""
    echo "Deployment Order:"
    echo "  1. Deploy infrastructure first (ArgoCD, Ingress-Nginx)"
    echo "  2. Then deploy appender-java to desired environment"
}

# =============================================================================
# ACTION EXECUTION
# =============================================================================

# Execute the selected action
execute_action() {
    local env=$1
    local action=$2
    
    case ${action,,} in  # ${action,,} converts to lowercase
        "infra")
            # Infrastructure deployment workflow
            check_prerequisites
            check_cluster
            set_cluster_context
            deploy_infrastructure
            wait_for_infrastructure
            show_infrastructure_status
            print_status "Infrastructure deployment completed successfully!"
            ;;
        "deploy")
            # Full deployment workflow
            check_prerequisites
            check_cluster
            set_cluster_context
            deploy_appender "$env"
            wait_for_appender "$env"
            show_status "$env"
            print_status "Appender-java deployment completed successfully!"
            ;;
        "status")
            # Show current status
            check_cluster
            set_cluster_context
            if [ "$env" = "infra" ]; then
                show_infrastructure_status
            else
                show_status "$env"
            fi
            ;;
        "test")
            # Test instance health
            check_cluster
            set_cluster_context
            test_chain "$env"
            ;;
        "delete")
            # Delete deployment
            check_cluster
            set_cluster_context
            remove_appender "$env"
            ;;
        "restart")
            # Restart appender pods
            check_cluster
            set_cluster_context
            restart_appender_pods "$env"
            ;;
        "portforward")
            # Just port forward to first appender pod
            check_cluster
            set_cluster_context
            port_forward_and_open "$env"
            ;;
        "help"|"-h"|"--help")
            # Show help
            show_help
            ;;
        *)
            # Unknown action
            print_error "Unknown action: $action"
            echo "Run '$0 help' for usage information"
            return 1
            ;;
    esac
}

# =============================================================================
# MAIN EXECUTION LOGIC
# =============================================================================

# Main function that routes to appropriate action based on command line arguments
main() {
    # If no arguments provided, run in interactive mode
    if [ $# -eq 0 ]; then
        interactive_mode
    else
        # Command line mode
        execute_action "$ENVIRONMENT" "$ACTION"
    fi
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

# Execute the main function
main "$@"
