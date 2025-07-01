# Appender Java Deployment Script for PowerShell
# This script deploys only the appender-java application using Helmfile

param(
    [Parameter(Position=0)]
    [string]$Environment = "dev",
    [Parameter(Position=1)]
    [string]$Action = "deploy"
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

# Get namespace based on environment
function Get-Namespace {
    param([string]$Env)
    switch ($Env.ToLower()) {
        "dev" { return "dev-appender-java" }
        "prod" { return "prod-appender-java" }
        default { 
            Write-Error "Invalid environment: $Env. Use 'dev' or 'prod'"
            exit 1
        }
    }
}

# Get instance count based on environment
function Get-InstanceCount {
    param([string]$Env)
    switch ($Env.ToLower()) {
        "dev" { return 3 }
        "prod" { return 10 }
        default { return 3 }
    }
}

# Deploy appender-java
function Start-Appender {
    param([string]$Env)
    $namespace = Get-Namespace $Env
    $instanceCount = Get-InstanceCount $Env
    
    Write-Status "Deploying appender-java to $Env environment"
    Write-Status "Namespace: $namespace"
    Write-Status "Instance count: $instanceCount"
    Write-Host ""
    
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location "$scriptDir/../helmfile"
    
    # Deploy using environment-specific helmfile
    if ($Env -eq "dev") {
        Write-Status "Using development environment configuration..."
        helmfile -e development apply --selector name=appender-java
    } elseif ($Env -eq "prod") {
        Write-Status "Using production environment configuration..."
        helmfile -e production apply --selector name=appender-java
    }
    
    Write-Status "Appender-java deployment completed"
}

# Wait for appender-java to be ready
function Wait-ForAppender {
    param([string]$Env)
    $namespace = Get-Namespace $Env
    $instanceCount = Get-InstanceCount $Env
    
    Write-Status "Waiting for appender-java instances to be ready in $Env environment..."
    
    for ($i = 1; $i -le $instanceCount; $i++) {
        $instanceName = "appender-java-{0:D2}" -f $i
        Write-Status "Waiting for $instanceName..."
        
        kubectl wait --for=condition=available --timeout=300s deployment/$instanceName -n $namespace
        
        if ($LASTEXITCODE -eq 0) {
            Write-Status "$instanceName is ready"
        } else {
            Write-Error "$instanceName failed to become ready"
        }
    }
    
    Write-Status "All appender-java instances are ready"
}

# Show deployment status
function Show-Status {
    param([string]$Env)
    $namespace = Get-Namespace $Env
    $instanceCount = Get-InstanceCount $Env
    
    Write-Status "Checking status for appender-java in $Env environment (namespace: $namespace)"
    Write-Host ""
    
    # Check deployments
    Write-Host "=== Deployments ===" -ForegroundColor Cyan
    kubectl get deployments -n $namespace --selector=app.kubernetes.io/name=appender-java
    
    Write-Host ""
    Write-Host "=== Services ===" -ForegroundColor Cyan
    kubectl get services -n $namespace --selector=app.kubernetes.io/name=appender-java
    
    Write-Host ""
    Write-Host "=== Pods ===" -ForegroundColor Cyan
    kubectl get pods -n $namespace --selector=app.kubernetes.io/name=appender-java
    
    Write-Host ""
    Write-Host "=== Instance Details ===" -ForegroundColor Cyan
    for ($i = 1; $i -le $instanceCount; $i++) {
        $instanceName = "appender-java-{0:D2}" -f $i
        $podName = kubectl get pods -n $namespace --selector="app.kubernetes.io/instance=$instanceName" -o jsonpath="{.items[0].metadata.name}" 2>$null
        if ($podName) {
            $status = kubectl get pod $podName -n $namespace -o jsonpath="{.status.phase}"
            $ready = kubectl get pod $podName -n $namespace -o jsonpath="{.status.containerStatuses[0].ready}"
            $nodeType = kubectl get pod $podName -n $namespace -o jsonpath="{.spec.containers[0].env[?(@.name=='NODE_TYPE')].value}"
            Write-Host "$instanceName : $status (Ready: $ready, Type: $nodeType)" -ForegroundColor $(if ($ready -eq "true") { "Green" } else { "Red" })
        } else {
            Write-Host "$instanceName : Not found" -ForegroundColor Red
        }
    }
}

# Delete appender-java
function Remove-Appender {
    param([string]$Env)
    
    Write-Warning "This will delete all appender-java instances in $Env environment"
    $confirmation = Read-Host "Are you sure you want to continue? (y/N)"
    
    if ($confirmation -eq "y" -or $confirmation -eq "Y") {
        Write-Status "Deleting appender-java from $Env environment..."
        
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        Set-Location "$scriptDir/../helmfile"
        
        if ($Env -eq "dev") {
            helmfile -e development delete --selector name=appender-java
        } elseif ($Env -eq "prod") {
            helmfile -e production delete --selector name=appender-java
        }
        
        Write-Status "Appender-java deletion completed"
    } else {
        Write-Status "Deletion cancelled"
    }
}

# Test the chain
function Test-Chain {
    param([string]$Env)
    $namespace = Get-Namespace $Env
    $instanceCount = Get-InstanceCount $Env
    
    Write-Status "Testing appender-java chain in $Env environment"
    Write-Host ""
    
    for ($i = 1; $i -le $instanceCount; $i++) {
        $instanceName = "appender-java-{0:D2}" -f $i
        $serviceName = "$instanceName-service"
        
        Write-Host "Testing $instanceName..." -NoNewline
        
        # Check if service exists
        $service = kubectl get service $serviceName -n $namespace 2>$null
        if ($service) {
            # Get the service port
            $port = kubectl get service $serviceName -n $namespace -o jsonpath="{.spec.ports[0].port}"
            
            # Try to port-forward and test health endpoint
            $job = Start-Job -ScriptBlock {
                param($namespace, $serviceName, $port)
                kubectl port-forward service/$serviceName "$port`:$port" -n $namespace 2>$null
            } -ArgumentList $namespace, $serviceName, $port
            
            Start-Sleep -Seconds 2
            
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:$port/actuator/health" -TimeoutSec 5 -ErrorAction Stop
                if ($response.StatusCode -eq 200) {
                    Write-Host " HEALTHY" -ForegroundColor Green
                } else {
                    Write-Host " UNHEALTHY (Status: $($response.StatusCode))" -ForegroundColor Red
                }
            } catch {
                Write-Host " UNHEALTHY (Connection failed)" -ForegroundColor Red
            } finally {
                Stop-Job $job -ErrorAction SilentlyContinue
                Remove-Job $job -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host " Service not found" -ForegroundColor Red
        }
    }
}

# Show help
function Show-Help {
    Write-Host "Usage: .\deploy-appender.ps1 [environment] [action]"
    Write-Host ""
    Write-Host "Environments:"
    Write-Host "  dev              Development environment (3 instances)"
    Write-Host "  prod             Production environment (10 instances)"
    Write-Host ""
    Write-Host "Actions:"
    Write-Host "  deploy           Deploy appender-java (default)"
    Write-Host "  status           Show deployment status"
    Write-Host "  test             Test the instance chain"
    Write-Host "  delete           Delete appender-java deployment"
    Write-Host "  help             Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\deploy-appender.ps1 dev deploy"
    Write-Host "  .\deploy-appender.ps1 prod status"
    Write-Host "  .\deploy-appender.ps1 dev test"
    Write-Host "  .\deploy-appender.ps1 prod delete"
}

# Main function
function Main {
    switch ($Action.ToLower()) {
        "deploy" {
            Test-Prerequisites
            Start-Appender $Environment
            Wait-ForAppender $Environment
            Show-Status $Environment
            Write-Status "Appender-java deployment completed successfully!"
        }
        "status" {
            Show-Status $Environment
        }
        "test" {
            Test-Chain $Environment
        }
        "delete" {
            Remove-Appender $Environment
        }
        "help" {
            Show-Help
        }
        "-h" {
            Show-Help
        }
        "--help" {
            Show-Help
        }
        default {
            Write-Error "Unknown action: $Action"
            Write-Host "Run '.\deploy-appender.ps1 help' for usage information"
            exit 1
        }
    }
}

# Run main function
Main 