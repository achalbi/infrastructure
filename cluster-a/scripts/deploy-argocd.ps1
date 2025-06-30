# ArgoCD Deployment Script for PowerShell
# This script deploys ArgoCD using Helmfile and manages the GitOps workflow

param(
    [Parameter(Position=0)]
    [string]$Command = "deploy"
)

# Function to print colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check if kubectl is available
function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Error "kubectl is not installed or not in PATH"
        exit 1
    }
    
    if (-not (Get-Command helmfile -ErrorAction SilentlyContinue)) {
        Write-Error "helmfile is not installed or not in PATH"
        exit 1
    }
    
    Write-Status "Prerequisites check passed"
}

# Deploy ArgoCD using Helmfile
function Start-ArgoCD {
    Write-Status "Deploying ArgoCD using Helmfile..."
    
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location "$scriptDir/../helmfile"
    
    # Deploy ArgoCD
    helmfile apply --selector name=argocd
    
    Write-Status "ArgoCD deployment completed"
}

# Wait for ArgoCD to be ready
function Wait-ForArgoCD {
    Write-Status "Waiting for ArgoCD to be ready..."
    
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    
    Write-Status "ArgoCD is ready"
}

# Get ArgoCD admin password
function Get-AdminPassword {
    Write-Status "Getting ArgoCD admin password..."
    
    # Get the admin password from the secret
    $ADMIN_PASSWORD = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
    
    Write-Host "=========================================="
    Write-Host "ArgoCD Admin Password: $ADMIN_PASSWORD"
    Write-Host "=========================================="
    Write-Warning "Please save this password securely"
}

# Port forward ArgoCD server
function Start-PortForward {
    Write-Status "Setting up port forward for ArgoCD server..."
    Write-Status "ArgoCD UI will be available at: http://localhost:8080"
    Write-Status "Username: admin"
    Write-Status "Press Ctrl+C to stop port forwarding"
    
    kubectl port-forward svc/argocd-server -n argocd 8080:443
}

# Deploy ArgoCD applications
function Start-Applications {
    Write-Status "Deploying ArgoCD applications..."
    
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location "$scriptDir/../argocd/applications"
    
    # Apply all ArgoCD applications
    kubectl apply -f .
    
    Write-Status "ArgoCD applications deployed"
}

# Main function
function Main {
    switch ($Command) {
        "deploy" {
            Test-Prerequisites
            Start-ArgoCD
            Wait-ForArgoCD
            Get-AdminPassword
            Start-Applications
            Write-Status "ArgoCD deployment completed successfully!"
            Write-Status "You can now access ArgoCD UI or run: .\deploy-argocd.ps1 port-forward"
        }
        "port-forward" {
            Start-PortForward
        }
        "applications" {
            Start-Applications
        }
        "password" {
            Get-AdminPassword
        }
        "help" {
            Write-Host "Usage: .\deploy-argocd.ps1 [command]"
            Write-Host ""
            Write-Host "Commands:"
            Write-Host "  deploy        Deploy ArgoCD and applications (default)"
            Write-Host "  port-forward  Start port forward to ArgoCD UI"
            Write-Host "  applications  Deploy only ArgoCD applications"
            Write-Host "  password      Get ArgoCD admin password"
            Write-Host "  help          Show this help message"
        }
        default {
            Write-Error "Unknown command: $Command"
            Write-Host "Run '.\deploy-argocd.ps1 help' for usage information"
            exit 1
        }
    }
}

# Run main function
Main 