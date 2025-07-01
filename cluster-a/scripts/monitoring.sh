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

# Check pre-install charts (OpenTelemetry instrumentation)
check_pre_install_charts() {
    print_header "Checking Pre-install Charts (OpenTelemetry Instrumentation)"
    
    # Check for OpenTelemetry instrumentation resources
    print_status "Checking OpenTelemetry Instrumentation resources..."
    
    # Check instrumentation resources
    instrumentation_list=$(kubectl get instrumentation --all-namespaces 2>/dev/null || true)
    if [ -n "$instrumentation_list" ]; then
        print_status "OpenTelemetry Instrumentation resources:"
        echo "$instrumentation_list"
    else
        print_warning "No OpenTelemetry Instrumentation resources found"
    fi
    
    # Check for pre-install namespaces
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | grep -E "(appender-java)" || true)
    
    for namespace in $namespaces; do
        print_status "Checking OpenTelemetry instrumentation in namespace: $namespace"
        
        # Check for instrumentation annotations on pods
        pods_with_instrumentation=$(kubectl get pods -n "$namespace" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.instrumentation\.opentelemetry\.io/inject-java}{"\n"}{end}' 2>/dev/null | grep -v "null" || true)
        if [ -n "$pods_with_instrumentation" ]; then
            print_status "Pods with OpenTelemetry instrumentation:"
            echo "$pods_with_instrumentation"
        fi
    done
}

# Check appender-java applications
check_appender_java_applications() {
    print_header "Checking Appender Java Applications"
    
    # Check for appender-java resources in all namespaces
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | grep "appender-java" || true)
    
    for namespace in $namespaces; do
        print_status "Checking appender-java in namespace: $namespace"
        
        # Check deployments
        print_status "Deployments:"
        kubectl get deployments -n "$namespace" | grep "appender-java" || true
        
        # Check pods
        print_status "Pods:"
        kubectl get pods -n "$namespace" | grep "appender-java" || true
        
        # Check services
        print_status "Services:"
        kubectl get services -n "$namespace" | grep "appender-java" || true
        
        # Check for failed pods
        failed_pods=$(kubectl get pods -n "$namespace" --no-headers | grep "appender-java" | grep -c "Failed\|CrashLoopBackOff\|Error" || true)
        if [ "$failed_pods" -gt 0 ]; then
            print_warning "Found $failed_pods failed appender-java pod(s) in namespace $namespace"
            kubectl get pods -n "$namespace" | grep "appender-java" | grep -E "Failed|CrashLoopBackOff|Error"
        fi
    done
}

# Check application health
check_application_health() {
    print_header "Checking Application Health"
    
    # Get all namespaces with applications
    app_namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | grep -E "(sample-app|monitoring|ingress-nginx|observability|cert-manager)" || true)
    
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

# Check OpenTelemetry components
check_opentelemetry() {
    print_header "Checking OpenTelemetry Components"
    
    # Check OpenTelemetry Collector
    print_status "OpenTelemetry Collector:"
    kubectl get pods -n observability | grep "opentelemetry-collector" || true
    
    # Check OpenTelemetry Operator
    print_status "OpenTelemetry Operator:"
    kubectl get pods -n observability | grep "opentelemetry-operator" || true
    
    # Check Instrumentation resources
    print_status "OpenTelemetry Instrumentation:"
    kubectl get instrumentation --all-namespaces || true
}

# Check logs for errors
check_logs() {
    print_header "Checking Recent Logs for Errors"
    
    # Check ArgoCD logs for errors
    print_status "ArgoCD Server Logs (last 50 lines with errors):"
    kubectl logs -n argocd deployment/argocd-server --tail=50 | grep -i error || true
    
    print_status "ArgoCD Application Controller Logs (last 50 lines with errors):"
    kubectl logs -n argocd deployment/argocd-application-controller --tail=50 | grep -i error || true
    
    # Check appender-java logs for errors
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | grep "appender-java" || true)
    for namespace in $namespaces; do
        print_status "Appender Java Logs in $namespace (last 20 lines with errors):"
        kubectl logs -n "$namespace" deployment/appender-java --tail=20 | grep -i error || true
    done
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
        
        echo "=== Pre-install Resources (OpenTelemetry Instrumentation) ==="
        kubectl get instrumentation --all-namespaces || true
        echo ""
        
        echo "=== Appender Java Applications ==="
        kubectl get deployments --all-namespaces | grep "appender-java" || true
        kubectl get pods --all-namespaces | grep "appender-java" || true
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
    
    # Check pre-install charts
    check_pre_install_charts
    echo ""
    
    # Check appender-java applications
    check_appender_java_applications
    echo ""
    
    # Check application health
    check_application_health
    echo ""
    
    # Check OpenTelemetry components
    check_opentelemetry
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