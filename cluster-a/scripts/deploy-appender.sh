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

# Use printf for colored output
default_print_header() {
    printf "%b%s%b\n" "$CYAN" "$1" "$NC"
}
default_print_option() {
    printf "%b%s%b\n" "$BLUE" "$1" "$NC"
}
# Replace print_header and print_option with new versions
print_header() { default_print_header "$1"; }
print_option() { default_print_option "$1"; }

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

    # Check if kind cluster exists
    if ! kind get clusters | grep -q "$CLUSTER_NAME"; then
        print_error "Cluster '$CLUSTER_NAME' not found. Available clusters:"
        kind get clusters
        exit 1
    fi

    # Check if kubectl context exists
    if ! kubectl config get-contexts | grep -q "kind-$CLUSTER_NAME"; then
        print_error "Kubernetes context 'kind-$CLUSTER_NAME' not found. Please ensure the cluster is properly configured."
        print_error "Available contexts:"
        kubectl config get-contexts
        exit 1
    fi

    # Check if kubectl can connect to the cluster
    if ! kubectl cluster-info --context "kind-$CLUSTER_NAME" &> /dev/null; then
        print_error "Cannot connect to cluster '$CLUSTER_NAME'. Please check your kubeconfig and cluster status."
        exit 1
    fi

    print_status "Connected to cluster: $CLUSTER_NAME"
}


# Set the correct kubectl context
set_cluster_context() {
    print_status "Setting kubectl context to kind-$CLUSTER_NAME..."
    kubectl config use-context "kind-$CLUSTER_NAME"
    
    # Verify the context was set correctly
    current_context=$(kubectl config current-context)
    if [ "$current_context" != "kind-$CLUSTER_NAME" ]; then
        print_error "Failed to set context to kind-$CLUSTER_NAME. Current context is: $current_context"
        print_error "Available contexts:"
        kubectl config get-contexts
        exit 1
    fi
    
    print_status "Successfully set context to: $current_context"
}

# =============================================================================
# INTERACTIVE MENU SYSTEM
# =============================================================================

# Show environment selection menu
env_menu() {
    print_header "=========================================="
    print_header "    Appender Java Deployment Manager"
    print_header "=========================================="
    echo ""
    print_header "Target Cluster: $CLUSTER_NAME"
    echo ""
    print_header "Select Environment:"
    print_option "1) Development"
    print_option "2) Production"
    print_option "3) Exit"
    echo ""
    sleep 0.2
}

# Show domain (app/infra) menu
domain_menu() {
    local env=$1
    print_header "=========================================="
    print_header "    Appender Java Deployment Manager"
    print_header "=========================================="
    echo ""
    print_header "Environment: $env"
    print_header "Select Domain:"
    print_option "1) Appender Java Application"
    print_option "2) Infrastructure"
    print_option "3) Back"
    echo ""
    sleep 0.2
}

# Show action menu for app or infra
action_menu() {
    local env=$1
    local domain=$2
    print_header "=========================================="
    print_header "    Appender Java Deployment Manager"
    print_header "=========================================="
    echo ""
    print_header "Environment: $env"
    print_header "Domain: $domain"
    echo ""
    if [ "$domain" = "infra" ]; then
        print_header "Infrastructure Actions:"
        print_option "1) Deploy Infrastructure (ArgoCD, Ingress-Nginx, cert-manager, OpenTelemetry Operator, OpenTelemetry Collector, OpenTelemetry Instrumentation)"
        print_option "2) Show Infrastructure Status"
        print_option "3) Clear Infrastructure"
        print_option "4) Back"
        echo ""
    else
        print_header "Appender Actions:"
        print_option "1) Deploy Appender"
        print_option "2) Show Status"
        print_option "3) Test Chain"
        print_option "4) Delete Appender"
        print_option "5) Restart Appender Pods"
        print_option "6) Port Forward to First Appender"
        print_option "7) Back"
        echo ""
    fi
    sleep 0.2
}

# Get environment selection
grab_env() {
    clear
    local choice
    env_menu
    read -p "Enter your choice (1-3): " choice
    case $choice in
        1) ENVIRONMENT="dev" ;;
        2) ENVIRONMENT="prod" ;;
        3) ENVIRONMENT="exit" ;;
        *) print_error "Invalid choice"; ENVIRONMENT="exit" ;;
    esac
    return 0
}

# Get domain selection
grab_domain() {
    clear
    local env=$1
    local choice
    domain_menu "$env"
    read -p "Enter your choice (1-3): " choice
    case $choice in
        1) DOMAIN="app" ;;
        2) DOMAIN="infra" ;;
        3) DOMAIN="back" ;;
        *) print_error "Invalid choice"; DOMAIN="back" ;;
    esac
    return 0
}

# Get action selection for app or infra
grab_action() {
    clear
    local env=$1
    local domain=$2
    local choice
    action_menu "$env" "$domain"
    if [ "$domain" = "infra" ]; then
        read -p "Enter your choice (1-4): " choice
        case $choice in
            1) ACTION="infra" ;;
            2) ACTION="status" ;;
            3) ACTION="clear" ;;
            4) ACTION="back" ;;
            *) print_error "Invalid choice"; ACTION="back" ;;
        esac
    else
        read -p "Enter your choice (1-7): " choice
        case $choice in
            1) ACTION="deploy" ;;
            2) ACTION="status" ;;
            3) ACTION="test" ;;
            4) ACTION="delete" ;;
            5) ACTION="restart" ;;
            6) ACTION="portforward" ;;
            7) ACTION="back" ;;
            *) print_error "Invalid choice"; ACTION="back" ;;
        esac
    fi
    return 0
}

# Refactored interactive_mode
interactive_mode() {
    while true; do
        grab_env
        if [ "$ENVIRONMENT" = "exit" ]; then
            print_status "Exiting..."
            exit 0
        fi
        while true; do
            grab_domain "$ENVIRONMENT"
            if [ "$DOMAIN" = "back" ]; then
                break
            fi
            while true; do
                grab_action "$ENVIRONMENT" "$DOMAIN"
                if [ "$ACTION" = "back" ]; then
                    break
                fi
                echo ""
                print_status "Executing: $ACTION on $DOMAIN in $ENVIRONMENT environment"
                echo ""
                execute_action "$ENVIRONMENT" "$ACTION"
                echo ""
                read -p "Press Enter to continue..."
            done
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
        "dev") echo "dev-appender-java" ;;
        "prod") echo "prod-appender-java" ;;
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

# Helper to get environment prefix
get_env_prefix() {
    local env=$1
    case ${env,,} in
        "dev") echo "dev-" ;;
        "prod") echo "prod-" ;;
        *) echo "" ;;
    esac
}

# Deploy infrastructure components (ArgoCD, Ingress-Nginx, cert-manager, OpenTelemetry Operator)
deploy_infrastructure() {
    local env=${1:-$ENVIRONMENT}
    local prefix=$(get_env_prefix "$env")
    print_status "Deploying infrastructure components to cluster: $CLUSTER_NAME for environment: $env (prefix: $prefix)"
    echo ""
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    helmfile_dir="$script_dir/../helmfile"
    
    if [ ! -d "$helmfile_dir" ]; then
        print_error "Helmfile directory not found: $helmfile_dir"
        print_error "Current directory: $(pwd)"
        print_error "Script directory: $script_dir"
        exit 1
    fi
    
    print_status "Navigating to helmfile directory: $helmfile_dir"
    cd "$helmfile_dir"

    # Deploy ArgoCD
    print_status "Deploying ArgoCD..."
    helmfile -e $env apply --selector name=${prefix}argocd
    # Wait for ArgoCD
    print_status "Waiting for ArgoCD..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n ${prefix}argocd || print_error "ArgoCD failed to become ready"

    # Deploy Ingress-Nginx
    print_status "Deploying Ingress-Nginx..."
    helmfile -e $env apply --selector name=${prefix}ingress-nginx
    # Wait for Ingress-Nginx
    print_status "Waiting for Ingress-Nginx..."
    kubectl wait --for=condition=available --timeout=300s deployment/ingress-nginx-controller -n ${prefix}ingress-nginx || print_error "Ingress-Nginx failed to become ready"

    # Deploy cert-manager
    print_status "Deploying cert-manager..."
    helmfile -e $env apply --selector name=${prefix}cert-manager
    # Wait for cert-manager
    print_status "Waiting for cert-manager..."
    kubectl get namespace ${prefix}cert-manager >/dev/null 2>&1 || kubectl create namespace ${prefix}cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n ${prefix}cert-manager || print_error "cert-manager failed to become ready"

    # Deploy OpenTelemetry Operator
    print_status "Deploying OpenTelemetry Operator..."
    helmfile -e $env apply --selector name=${prefix}opentelemetry-operator
    # Wait for OpenTelemetry Operator
    print_status "Waiting for OpenTelemetry Operator..."
    kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-operator -n ${prefix}observability || print_error "OpenTelemetry Operator failed to become ready"

    # Deploy OpenTelemetry Collector (Deployment)
    print_status "Deploying OpenTelemetry Collector (Deployment)..."
    helmfile -e $env apply --selector name=${prefix}opentelemetry-collector-deployment
    # Wait for OpenTelemetry Collector Deployment
    print_status "Waiting for OpenTelemetry Collector Deployment..."
    kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-collector-deployment -n ${prefix}observability || print_error "OpenTelemetry Collector Deployment failed to become ready"

    # Deploy OpenTelemetry Collector (DaemonSet)
    print_status "Deploying OpenTelemetry Collector (DaemonSet)..."
    helmfile -e $env apply --selector name=${prefix}opentelemetry-collector-daemonset
    # Wait for OpenTelemetry Collector DaemonSet
    print_status "Waiting for OpenTelemetry Collector DaemonSet..."
    kubectl rollout status daemonset/opentelemetry-collector-daemonset-agent -n ${prefix}observability --timeout=300s || print_error "OpenTelemetry Collector DaemonSet failed to become ready"

    # Deploy pre-install charts (OpenTelemetry instrumentation)
    print_status "Deploying pre-install charts (OpenTelemetry instrumentation)..."
        
    # Deploy using environment-specific helmfile configuration
    case $env in
        "dev")
            print_status "Using development environment configuration..."
            # Deploy using the development environment helmfile
            helmfile -f environments/development/helmfile.yaml apply --selector name=pre-install
            ;;
        "prod")
            print_status "Using production environment configuration..."
            # Deploy using the production environment helmfile
            helmfile -f environments/production/helmfile.yaml apply --selector name=pre-install
            ;;
    esac

    print_status "pre-install resources created..."

    print_status "All infrastructure components deployed and ready"
}

# Wait for infrastructure components to be ready
wait_for_infrastructure() {
    local env=$1
    local prefix=""
    if [ "$env" = "dev" ]; then
        prefix="dev-"
    elif [ "$env" = "prod" ]; then
        prefix="prod-"
    else
        print_error "Unknown environment: $env"
        return 1
    fi

    print_status "Waiting for infrastructure components to be ready..."

    # Wait for ArgoCD
    print_status "Waiting for ArgoCD..."
    if kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n ${prefix}argocd; then
        print_status "ArgoCD is ready"
    else
        print_error "ArgoCD failed to become ready"
    fi

    # Wait for Ingress-Nginx
    print_status "Waiting for Ingress-Nginx..."
    if kubectl wait --for=condition=available --timeout=300s deployment/ingress-nginx-controller -n ${prefix}ingress-nginx; then
        print_status "Ingress-Nginx is ready"
    else
        print_error "Ingress-Nginx failed to become ready"
    fi

    # Wait for cert-manager
    print_status "Waiting for cert-manager..."
    if kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n ${prefix}cert-manager; then
        print_status "cert-manager is ready"
    else
        print_error "cert-manager failed to become ready"
    fi

    # Wait for OpenTelemetry Operator
    print_status "Waiting for OpenTelemetry Operator..."
    if kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-operator -n ${prefix}observability; then
        print_status "OpenTelemetry Operator is ready"
    else
        print_error "OpenTelemetry Operator failed to become ready"
    fi

    # Wait for OpenTelemetry Collector Deployment
    print_status "Waiting for OpenTelemetry Collector Deployment..."
    if kubectl wait --for=condition=available --timeout=300s deployment/opentelemetry-collector-deployment -n ${prefix}observability; then
        print_status "OpenTelemetry Collector Deployment is ready"
    else
        print_error "OpenTelemetry Collector Deployment failed to become ready"
    fi

    # Wait for OpenTelemetry Collector DaemonSet
    print_status "Waiting for OpenTelemetry Collector DaemonSet..."
    if kubectl rollout status daemonset/opentelemetry-collector-daemonset-agent -n ${prefix}observability --timeout=300s; then
        print_status "OpenTelemetry Collector DaemonSet is ready"
    else
        print_error "OpenTelemetry Collector DaemonSet failed to become ready"
    fi

    # Wait for instrumentation
    print_status "Waiting for instrumentation..."
    if kubectl get instrumentation/java-instrumentation -n ${prefix}appender-java; then
        print_status "instrumentation is ready"
    else
        print_error "instrumentation failed to become ready"
    fi
}

# Show infrastructure status
show_infrastructure_status() {
    local env=$1
    local prefix=""
    if [ "$env" = "dev" ]; then
        prefix="dev-"
    elif [ "$env" = "prod" ]; then
        prefix="prod-"
    else
        print_error "Unknown environment: $env"
        return 1
    fi

    print_status "Checking infrastructure status for cluster: $CLUSTER_NAME (environment: $env)"
    echo ""

    # ArgoCD
    local argocd_ns="${prefix}argocd"
    echo -e "${CYAN}=== ArgoCD Status (${argocd_ns}) ===${NC}"
    kubectl get deployments -n "$argocd_ns" || true
    echo ""
    kubectl get services -n "$argocd_ns" || true
    echo ""
    kubectl get pods -n "$argocd_ns" || true

    echo ""
    # Ingress-Nginx
    local ingress_ns="${prefix}ingress-nginx"
    echo -e "${CYAN}=== Ingress-Nginx Status (${ingress_ns}) ===${NC}"
    kubectl get deployments -n "$ingress_ns" || true
    echo ""
    kubectl get services -n "$ingress_ns" || true
    echo ""
    kubectl get pods -n "$ingress_ns" || true

    echo ""
    # cert-manager
    local cert_ns="${prefix}cert-manager"
    echo -e "${CYAN}=== cert-manager Status (${cert_ns}) ===${NC}"
    kubectl get deployments -n "$cert_ns" || true
    echo ""
    kubectl get services -n "$cert_ns" || true
    echo ""
    kubectl get pods -n "$cert_ns" || true

    echo ""
    # OpenTelemetry Operator & Collector
    local obs_ns="${prefix}observability"
    echo -e "${CYAN}=== OpenTelemetry Operator Status (${obs_ns}) ===${NC}"
    kubectl get deployments -n "$obs_ns" || true
    echo ""
    kubectl get services -n "$obs_ns" || true
    echo ""
    kubectl get pods -n "$obs_ns" || true

    echo ""
    echo -e "${CYAN}=== OpenTelemetry Collector Status (${obs_ns}) ===${NC}"
    # Show Deployment status
    kubectl get deployments -n "$obs_ns" | grep "opentelemetry-collector-deployment" || true
    # Show DaemonSet status
    kubectl get daemonsets -n "$obs_ns" | grep "opentelemetry-collector-daemonset-agent" || true
    # Show Services
    kubectl get services -n "$obs_ns" | grep "opentelemetry-collector" || true
    # Show Pods for both deployment and daemonset
    kubectl get pods -n "$obs_ns" | grep "opentelemetry-collector" || true

    echo ""
    local appender_java_ns="${prefix}appender-java"
    echo -e "${CYAN}=== OpenTelemetry Instrumentation (${appender_java_ns}) ===${NC}"
    #show instrumentation
    kubectl get instrumentation -n "$appender_java_ns" | grep "java-instrumentation" || true
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
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    helmfile_dir="$script_dir/../helmfile"
    
    if [ ! -d "$helmfile_dir" ]; then
        print_error "Helmfile directory not found: $helmfile_dir"
        print_error "Current directory: $(pwd)"
        print_error "Script directory: $script_dir"
        exit 1
    fi
    
    print_status "Navigating to helmfile directory: $helmfile_dir"
    cd "$helmfile_dir"
    
    # Deploy using environment-specific helmfile configuration
    case $env in
        "dev")
            print_status "Using development environment configuration..."
            # Deploy using the development environment helmfile
            helmfile -f environments/development/helmfile.yaml apply --selector name=appender-java
            ;;
        "prod")
            print_status "Using production environment configuration..."
            # Deploy using the production environment helmfile
            helmfile -f environments/production/helmfile.yaml apply --selector name=appender-java
            ;;
    esac
    
    print_status "Appender-java deployment completed"
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
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        helmfile_dir="$script_dir/../helmfile"
        
        if [ ! -d "$helmfile_dir" ]; then
            print_error "Helmfile directory not found: $helmfile_dir"
            print_error "Current directory: $(pwd)"
            print_error "Script directory: $script_dir"
            exit 1
        fi
        
        print_status "Navigating to helmfile directory: $helmfile_dir"
        cd "$helmfile_dir"
        
        # Delete using environment-specific helmfile
        case $env in
            "dev")
                helmfile -f environments/development/helmfile.yaml delete --selector name=appender-java
                ;;
            "prod")
                helmfile -f environments/production/helmfile.yaml delete --selector name=appender-java
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
    sleep 2
    # Wait for all appender-java pods to be restarted and running before continuing
    print_status "Waiting for all appender-java pods to be restarted and running in namespace $namespace..."

    for ((i=1; i<=instance_count; i++)); do
        instance_name=$(printf "appender-java-%02d" $i)
        print_status "Checking rollout status for deployment/$instance_name..."

        # Wait for deployment rollout to complete (ensures pods are restarted)
        if ! kubectl rollout status deployment/$instance_name -n $namespace --timeout=180s; then
            print_error "Deployment $instance_name did not complete rollout in time."
            continue
        fi

        # Get the list of pods for this deployment
        pod_selector="app.kubernetes.io/instance=$instance_name"
        pods=($(kubectl get pods -n $namespace -l "$pod_selector" -o jsonpath='{.items[*].metadata.name}'))

        if [ ${#pods[@]} -eq 0 ]; then
            print_warning "No pods found for $instance_name after rollout."
            continue
        fi

        # For each pod, check that it was restarted recently and is running
        for pod in "${pods[@]}"; do
            # Get pod phase
            phase=$(kubectl get pod "$pod" -n $namespace -o jsonpath='{.status.phase}')
            # Get pod start time (in seconds since epoch)
            start_time=$(kubectl get pod "$pod" -n $namespace -o jsonpath='{.status.startTime}')
            start_time_epoch=$(date -d "$start_time" +%s 2>/dev/null)
            now_epoch=$(date +%s)
            # Consider "recent" as within the last 3 minutes (180 seconds)
            if [[ "$phase" == "Running" && $((now_epoch - start_time_epoch)) -le 180 ]]; then
                print_status "Pod $pod for $instance_name is running and was recently restarted."
            elif [[ "$phase" == "Running" ]]; then
                print_warning "Pod $pod for $instance_name is running, but may not have been restarted recently."
            else
                print_error "Pod $pod for $instance_name is not running (phase: $phase)."
            fi
        done

        # Wait until all pods for this deployment are running
        desired_replicas=$(kubectl get deployment $instance_name -n $namespace -o jsonpath='{.spec.replicas}' 2>/dev/null)
        for attempt in {1..18}; do
            running_count=$(kubectl get pods -n $namespace -l "$pod_selector" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
            if [[ "$running_count" -ge "${desired_replicas:-1}" ]]; then
                break
            fi
            sleep 5
        done

        # Final check
        running_count=$(kubectl get pods -n $namespace -l "$pod_selector" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [[ "$running_count" -lt "${desired_replicas:-1}" ]]; then
            print_warning "Not all pods for $instance_name are running after waiting."
        else
            print_status "All pods for $instance_name are running."
        fi
    done
    print_status "All appender-java pods have been restarted."
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


# Stub for clearing infrastructure
clear_infrastructure() {
    local env=$1
    local prefix=""
    if [ "$env" = "dev" ]; then
        prefix="dev-"
    elif [ "$env" = "prod" ]; then
        prefix="prod-"
    else
        print_error "Unknown environment: $env"
        return 1
    fi

    echo ""
    print_warning "This will delete ALL infrastructure components in the ${prefix}* namespaces for environment: $env!"
    read -p "Are you sure you want to continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "Aborted infrastructure deletion."
        return 0
    fi

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    helmfile_dir="$script_dir/../helmfile"
    cd "$helmfile_dir"

    # Delete in reverse dependency order
    print_status "Deleting OpenTelemetry Operator..."
    helmfile -e "$env" destroy --selector name="${prefix}opentelemetry-operator"

    print_status "Deleting OpenTelemetry Collector (Deployment)..."
    helmfile -e "$env" destroy --selector name="${prefix}opentelemetry-collector-deployment"

    print_status "Deleting OpenTelemetry Collector (DaemonSet)..."
    helmfile -e "$env" destroy --selector name="${prefix}opentelemetry-collector-daemonset"

    print_status "Deleting cert-manager..."
    helmfile -e "$env" destroy --selector name="${prefix}cert-manager"

    print_status "Deleting Ingress-Nginx..."
    helmfile -e "$env" destroy --selector name="${prefix}ingress-nginx"

    print_status "Deleting ArgoCD..."
    helmfile -e "$env" destroy --selector name="${prefix}argocd"

    print_status "All infrastructure components deleted for environment: $env"
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
    echo "  Note: This script will automatically switch to the kind-$CLUSTER_NAME context"
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
    
    # Always set cluster context first for all actions except help
    if [[ "${action,,}" != "help" && "${action,,}" != "-h" && "${action,,}" != "--help" ]]; then
        check_prerequisites
        check_cluster
        set_cluster_context
    fi
    
    case ${action,,} in  # ${action,,} converts to lowercase
        "infra")
            # Infrastructure deployment workflow
            deploy_infrastructure "$env"
            wait_for_infrastructure "$env"
            show_infrastructure_status "$env"
            print_status "Infrastructure deployment completed successfully!"
            ;;
        "clear")
            clear_infrastructure "$env"
            ;;
        "deploy")
            # Full deployment workflow
            deploy_appender "$env"
            wait_for_appender "$env"
            show_status "$env"
            print_status "Appender-java deployment completed successfully!"
            port_forward_and_open "$env"
            ;;
        "status")
            # Show current status
            if [[ "$env" == infra* ]]; then
                show_infrastructure_status "$env"
            else
                show_status "$env"
            fi
            ;;
        "test")
            # Test instance health
            test_chain "$env"
            ;;
        "delete")
            # Delete deployment
            remove_appender "$env"
            ;;
        "restart")
            # Restart appender pods
            restart_appender_pods "$env"
            port_forward_and_open "$env"
            ;;
        "portforward")
            # Just port forward to first appender pod
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
