#!/bin/bash

# Multiple Instances Management Script for Bash
# This script helps manage multiple appender-java instances

# Default values
COMMAND=${1:-"status"}
ENVIRONMENT=${2:-"dev"}
INSTANCE_COUNT=${3:-0}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

# Get namespace based on environment
get_namespace() {
    local env=$1
    case ${env,,} in
        "dev") echo "dev-appender-java" ;;
        "prod") echo "prod-appender-java" ;;
        *) echo "appender-java" ;;
    esac
}

# Get instance count based on environment
get_instance_count() {
    local env=$1
    case ${env,,} in
        "dev") echo 3 ;;
        "prod") echo 10 ;;
        *) echo 10 ;;
    esac
}

# Show status of all instances
show_instance_status() {
    local env=$1
    local namespace=$(get_namespace "$env")
    local instance_count=$(get_instance_count "$env")
    
    print_status "Checking status for environment: $env (namespace: $namespace)"
    echo ""
    
    # Check deployments
    echo -e "${CYAN}=== Deployments ===${NC}"
    kubectl get deployments -n "$namespace" --selector=app.kubernetes.io/name=appender-java
    
    echo ""
    echo -e "${CYAN}=== Services ===${NC}"
    kubectl get services -n "$namespace" --selector=app.kubernetes.io/name=appender-java
    
    echo ""
    echo -e "${CYAN}=== Pods ===${NC}"
    kubectl get pods -n "$namespace" --selector=app.kubernetes.io/name=appender-java
    
    echo ""
    echo -e "${CYAN}=== Instance Details ===${NC}"
    for ((i=1; i<=instance_count; i++)); do
        instance_name=$(printf "appender-java-%02d" $i)
        pod_name=$(kubectl get pods -n "$namespace" --selector="app.kubernetes.io/instance=$instance_name" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
        
        if [ -n "$pod_name" ]; then
            status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath="{.status.phase}")
            ready=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath="{.status.containerStatuses[0].ready}")
            
            if [ "$ready" = "true" ]; then
                echo -e "${GREEN}$instance_name : $status (Ready: $ready)${NC}"
            else
                echo -e "${RED}$instance_name : $status (Ready: $ready)${NC}"
            fi
        else
            echo -e "${RED}$instance_name : Not found${NC}"
        fi
    done
}

# Scale instances
set_instance_count() {
    local env=$1
    local count=$2
    
    print_status "Scaling instances in $env environment to $count instances"
    
    # Update the helmfile values
    script_dir=$(dirname "$0")
    helmfile_path="$script_dir/../helmfile"
    
    case $env in
        "dev")
            env_file="$helmfile_path/environments/development/helmfile.yaml"
            ;;
        "prod")
            env_file="$helmfile_path/environments/production/helmfile.yaml"
            ;;
        *)
            env_file="$helmfile_path/helmfile.yaml"
            ;;
    esac
    
    # Update the count in the helmfile
    if [ -f "$env_file" ]; then
        sed -i "s/count: [0-9]*/count: $count/" "$env_file"
        print_status "Updated helmfile configuration. Run 'helmfile apply' to apply changes."
    else
        print_error "Helmfile not found: $env_file"
        exit 1
    fi
}

# Get logs from specific instance
get_instance_logs() {
    local env=$1
    local instance_number=$2
    local namespace=$(get_namespace "$env")
    local instance_name=$(printf "appender-java-%02d" $instance_number)
    
    print_status "Getting logs for $instance_name in $env environment"
    
    pod_name=$(kubectl get pods -n "$namespace" --selector="app.kubernetes.io/instance=$instance_name" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    
    if [ -n "$pod_name" ]; then
        kubectl logs "$pod_name" -n "$namespace" -f
    else
        print_error "Pod for instance $instance_name not found"
        exit 1
    fi
}

# Restart specific instance
restart_instance() {
    local env=$1
    local instance_number=$2
    local namespace=$(get_namespace "$env")
    local instance_name=$(printf "appender-java-%02d" $instance_number)
    
    print_status "Restarting $instance_name in $env environment"
    
    kubectl rollout restart deployment/"$instance_name" -n "$namespace"
    kubectl rollout status deployment/"$instance_name" -n "$namespace"
}

# Check health of all instances
test_instance_health() {
    local env=$1
    local namespace=$(get_namespace "$env")
    local instance_count=$(get_instance_count "$env")
    
    print_status "Checking health for all instances in $env environment"
    echo ""
    
    for ((i=1; i<=instance_count; i++)); do
        instance_name=$(printf "appender-java-%02d" $i)
        service_name="$instance_name-service"
        
        # Check if service exists
        if kubectl get service "$service_name" -n "$namespace" >/dev/null 2>&1; then
            # Try to get the service port
            port=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath="{.spec.ports[0].port}")
            
            echo -n "Testing $instance_name on port $port..."
            
            # Try to port-forward and test health endpoint
            kubectl port-forward service/"$service_name" "$port:$port" -n "$namespace" >/dev/null 2>&1 &
            port_forward_pid=$!
            
            # Wait a moment for port-forward to establish
            sleep 2
            
            # Test health endpoint
            if curl -s -f "http://localhost:$port/actuator/health" >/dev/null 2>&1; then
                echo -e " ${GREEN}HEALTHY${NC}"
            else
                echo -e " ${RED}UNHEALTHY${NC}"
            fi
            
            # Kill port-forward process
            kill $port_forward_pid 2>/dev/null
            wait $port_forward_pid 2>/dev/null
        else
            echo -e "${RED}$instance_name : Service not found${NC}"
        fi
    done
}

# Show help
show_help() {
    echo "Usage: $0 [command] [environment] [options]"
    echo ""
    echo "Commands:"
    echo "  status [env]     Show status of all instances (default: dev)"
    echo "  scale [env] [n]  Scale to n instances (default: dev)"
    echo "  logs [env] [n]   Get logs for instance n (default: dev)"
    echo "  restart [env] [n] Restart instance n (default: dev)"
    echo "  health [env]     Test health of all instances (default: dev)"
    echo "  help             Show this help message"
    echo ""
    echo "Environments:"
    echo "  dev              Development environment (3 instances)"
    echo "  prod             Production environment (10 instances)"
    echo ""
    echo "Examples:"
    echo "  $0 status prod"
    echo "  $0 scale dev 5"
    echo "  $0 logs prod 3"
}

# Main function
main() {
    case ${COMMAND,,} in
        "status")
            show_instance_status "$ENVIRONMENT"
            ;;
        "scale")
            if [ "$INSTANCE_COUNT" -eq 0 ]; then
                print_error "Please specify instance count: $0 scale <env> <count>"
                exit 1
            fi
            set_instance_count "$ENVIRONMENT" "$INSTANCE_COUNT"
            ;;
        "logs")
            if [ "$INSTANCE_COUNT" -eq 0 ]; then
                print_error "Please specify instance number: $0 logs <env> <instance-number>"
                exit 1
            fi
            get_instance_logs "$ENVIRONMENT" "$INSTANCE_COUNT"
            ;;
        "restart")
            if [ "$INSTANCE_COUNT" -eq 0 ]; then
                print_error "Please specify instance number: $0 restart <env> <instance-number>"
                exit 1
            fi
            restart_instance "$ENVIRONMENT" "$INSTANCE_COUNT"
            ;;
        "health")
            test_instance_health "$ENVIRONMENT"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed or not in PATH"
        exit 1
    fi
}

# Run main function
check_prerequisites
main 