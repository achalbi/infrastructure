#!/bin/bash

# Monitoring script for infrastructure and applications
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

# Check Kubernetes cluster health
check_kubernetes_cluster() {
    print_header "Checking Kubernetes Cluster Health"
    
    # Check cluster info
    print_status "Cluster Information:"
    kubectl cluster-info
    
    # Check nodes
    print_status "Node Status:"
    kubectl get nodes -o wide
    
    # Check for not ready nodes
    not_ready_nodes=$(kubectl get nodes --no-headers | grep -c "NotReady" || true)
    if [ "$not_ready_nodes" -gt 0 ]; then
        print_warning "Found $not_ready_nodes node(s) not ready"
        kubectl get nodes | grep "NotReady"
    else
        print_status "All nodes are ready"
    fi
}

# Check ArgoCD health
check_argocd_health() {
    print_header "Checking ArgoCD Health"
    
    # Check ArgoCD pods
    print_status "ArgoCD Pods:"
    kubectl get pods -n argocd
    
    # Check ArgoCD applications
    print_status "ArgoCD Applications:"
    kubectl get applications -n argocd
    
    # Check for failed applications
    failed_apps=$(kubectl get applications -n argocd --no-headers | grep -c "Failed" || true)
    if [ "$failed_apps" -gt 0 ]; then
        print_warning "Found $failed_apps failed application(s)"
        kubectl get applications -n argocd | grep "Failed"
    else
        print_status "All ArgoCD applications are healthy"
    fi
}

# Check Helmfile releases
check_helmfile_releases() {
    print_header "Checking Helmfile Releases"
    
    if [ -d "helmfile" ]; then
        cd helmfile
        
        print_status "Helmfile Releases:"
        helmfile list
        
        cd ..
    else
        print_warning "Helmfile directory not found"
    fi
}

# Check application health
check_application_health() {
    print_header "Checking Application Health"
    
    # Get all namespaces with applications
    app_namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | grep -E "(sample-app|monitoring|ingress-nginx)" || true)
    
    for namespace in $app_namespaces; do
        print_status "Checking namespace: $namespace"
        
        # Check pods
        kubectl get pods -n "$namespace"
        
        # Check services
        kubectl get services -n "$namespace"
        
        # Check for failed pods
        failed_pods=$(kubectl get pods -n "$namespace" --no-headers | grep -c "Failed\|CrashLoopBackOff\|Error" || true)
        if [ "$failed_pods" -gt 0 ]; then
            print_warning "Found $failed_pods failed pod(s) in namespace $namespace"
            kubectl get pods -n "$namespace" | grep -E "Failed|CrashLoopBackOff|Error"
        fi
    done
}

# Check resource usage
check_resource_usage() {
    print_header "Checking Resource Usage"
    
    # Check node resource usage
    print_status "Node Resource Usage:"
    kubectl top nodes
    
    # Check pod resource usage
    print_status "Pod Resource Usage:"
    kubectl top pods --all-namespaces
    
    # Check for high resource usage
    print_status "Checking for high CPU usage (>80%):"
    kubectl top nodes --no-headers | awk '$3 > 80 {print $1 " CPU: " $3 "%"}'
    
    print_status "Checking for high memory usage (>80%):"
    kubectl top nodes --no-headers | awk '$5 > 80 {print $1 " Memory: " $5 "%"}'
}

# Check storage
check_storage() {
    print_header "Checking Storage"
    
    # Check persistent volumes
    print_status "Persistent Volumes:"
    kubectl get pv
    
    # Check persistent volume claims
    print_status "Persistent Volume Claims:"
    kubectl get pvc --all-namespaces
    
    # Check for pending PVCs
    pending_pvcs=$(kubectl get pvc --all-namespaces --no-headers | grep -c "Pending" || true)
    if [ "$pending_pvcs" -gt 0 ]; then
        print_warning "Found $pending_pvcs pending PVC(s)"
        kubectl get pvc --all-namespaces | grep "Pending"
    fi
}

# Check network connectivity
check_network() {
    print_header "Checking Network Connectivity"
    
    # Check services
    print_status "Services:"
    kubectl get services --all-namespaces
    
    # Check ingress
    print_status "Ingress:"
    kubectl get ingress --all-namespaces
    
    # Check endpoints
    print_status "Endpoints:"
    kubectl get endpoints --all-namespaces
}

# Check logs for errors
check_logs() {
    print_header "Checking Recent Logs for Errors"
    
    # Check ArgoCD logs for errors
    print_status "ArgoCD Server Logs (last 50 lines with errors):"
    kubectl logs -n argocd deployment/argocd-server --tail=50 | grep -i error || true
    
    print_status "ArgoCD Application Controller Logs (last 50 lines with errors):"
    kubectl logs -n argocd deployment/argocd-application-controller --tail=50 | grep -i error || true
}

# Generate health report
generate_health_report() {
    print_header "Generating Health Report"
    
    local report_file="health_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=== Infrastructure Health Report ==="
        echo "Generated: $(date)"
        echo ""
        
        echo "=== Kubernetes Cluster ==="
        kubectl cluster-info
        echo ""
        
        echo "=== Nodes ==="
        kubectl get nodes -o wide
        echo ""
        
        echo "=== ArgoCD Applications ==="
        kubectl get applications -n argocd
        echo ""
        
        echo "=== All Pods Status ==="
        kubectl get pods --all-namespaces
        echo ""
        
        echo "=== Resource Usage ==="
        kubectl top nodes
        echo ""
        
    } > "$report_file"
    
    print_status "Health report generated: $report_file"
}

# Main monitoring function
main() {
    print_status "Starting infrastructure monitoring..."
    
    # Check cluster health
    check_kubernetes_cluster
    echo ""
    
    # Check ArgoCD health
    check_argocd_health
    echo ""
    
    # Check Helmfile releases
    check_helmfile_releases
    echo ""
    
    # Check application health
    check_application_health
    echo ""
    
    # Check resource usage
    check_resource_usage
    echo ""
    
    # Check storage
    check_storage
    echo ""
    
    # Check network
    check_network
    echo ""
    
    # Check logs
    check_logs
    echo ""
    
    # Generate report
    generate_health_report
    
    print_status "Monitoring completed!"
}

# Run main function
main "$@" 