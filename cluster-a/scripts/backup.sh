#!/bin/bash

# Backup script for infrastructure and applications
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

# Configuration
BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup_${DATE}"

# Create backup directory
create_backup_dir() {
    print_status "Creating backup directory..."
    mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}"
}

# Backup Kubernetes resources
backup_kubernetes_resources() {
    print_status "Backing up Kubernetes resources..."
    
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}/kubernetes"
    mkdir -p "$backup_path"
    
    # Get all namespaces
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
    
    for namespace in $namespaces; do
        print_status "Backing up namespace: $namespace"
        mkdir -p "$backup_path/$namespace"
        
        # Backup all resources in the namespace
        kubectl get all -n "$namespace" -o yaml > "$backup_path/$namespace/all-resources.yaml" 2>/dev/null || true
        
        # Backup configmaps
        kubectl get configmaps -n "$namespace" -o yaml > "$backup_path/$namespace/configmaps.yaml" 2>/dev/null || true
        
        # Backup secrets (without sensitive data)
        kubectl get secrets -n "$namespace" -o yaml > "$backup_path/$namespace/secrets.yaml" 2>/dev/null || true
        
        # Backup persistent volume claims
        kubectl get pvc -n "$namespace" -o yaml > "$backup_path/$namespace/persistent-volume-claims.yaml" 2>/dev/null || true
    done
    
    # Backup cluster-wide resources
    kubectl get nodes -o yaml > "$backup_path/nodes.yaml" 2>/dev/null || true
    kubectl get pv -o yaml > "$backup_path/persistent-volumes.yaml" 2>/dev/null || true
    kubectl get storageclasses -o yaml > "$backup_path/storage-classes.yaml" 2>/dev/null || true
}

# Backup Terraform state
backup_terraform_state() {
    print_status "Backing up Terraform state..."
    
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}/terraform"
    mkdir -p "$backup_path"
    
    if [ -d "terraform" ]; then
        cd terraform
        
        # Backup terraform.tfstate if it exists
        if [ -f "terraform.tfstate" ]; then
            cp terraform.tfstate "$backup_path/"
        fi
        
        # Backup terraform.tfstate.backup if it exists
        if [ -f "terraform.tfstate.backup" ]; then
            cp terraform.tfstate.backup "$backup_path/"
        fi
        
        # Backup .terraform directory
        if [ -d ".terraform" ]; then
            cp -r .terraform "$backup_path/"
        fi
        
        cd ..
    fi
}

# Backup Helmfile state
backup_helmfile_state() {
    print_status "Backing up Helmfile state..."
    
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}/helmfile"
    mkdir -p "$backup_path"
    
    if [ -d "helmfile" ]; then
        cd helmfile
        
        # Export Helm releases
        helmfile list --output json > "$backup_path/releases.json" 2>/dev/null || true
        
        # Backup values files
        find . -name "*.yaml" -o -name "*.yml" | while read -r file; do
            mkdir -p "$backup_path/$(dirname "$file")"
            cp "$file" "$backup_path/$file"
        done
        
        cd ..
    fi
}

# Backup ArgoCD applications
backup_argocd_applications() {
    print_status "Backing up ArgoCD applications..."
    
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}/argocd"
    mkdir -p "$backup_path"
    
    # Backup ArgoCD applications
    kubectl get applications -n argocd -o yaml > "$backup_path/applications.yaml" 2>/dev/null || true
    
    # Backup ArgoCD projects
    kubectl get appprojects -n argocd -o yaml > "$backup_path/projects.yaml" 2>/dev/null || true
    
    # Backup ArgoCD repositories
    kubectl get repositories -n argocd -o yaml > "$backup_path/repositories.yaml" 2>/dev/null || true
}

# Create backup archive
create_backup_archive() {
    print_status "Creating backup archive..."
    
    cd "$BACKUP_DIR"
    tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
    rm -rf "$BACKUP_NAME"
    
    print_status "Backup archive created: ${BACKUP_NAME}.tar.gz"
}

# Cleanup old backups
cleanup_old_backups() {
    print_status "Cleaning up old backups (keeping last 7 days)..."
    
    find "$BACKUP_DIR" -name "backup_*.tar.gz" -mtime +7 -delete 2>/dev/null || true
}

# Main backup function
main() {
    print_status "Starting backup process..."
    
    # Create backup directory
    create_backup_dir
    
    # Perform backups
    backup_kubernetes_resources
    backup_terraform_state
    backup_helmfile_state
    backup_argocd_applications
    
    # Create archive
    create_backup_archive
    
    # Cleanup old backups
    cleanup_old_backups
    
    print_status "Backup completed successfully!"
    print_status "Backup location: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
}

# Run main function
main "$@" 