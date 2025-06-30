# Multiple Instances Management Script for PowerShell
# This script helps manage multiple appender-java instances

param(
    [Parameter(Position=0)]
    [string]$Command = "status",
    [Parameter(Position=1)]
    [string]$Environment = "dev",
    [Parameter(Position=2)]
    [int]$InstanceCount = 0
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

# Get namespace based on environment
function Get-Namespace {
    param([string]$Env)
    switch ($Env.ToLower()) {
        "dev" { return "appender-java-dev" }
        "prod" { return "appender-java-prod" }
        default { return "appender-java" }
    }
}

# Get instance count based on environment
function Get-InstanceCount {
    param([string]$Env)
    switch ($Env.ToLower()) {
        "dev" { return 3 }
        "prod" { return 10 }
        default { return 10 }
    }
}

# Show status of all instances
function Show-InstanceStatus {
    param([string]$Env)
    $namespace = Get-Namespace $Env
    $instanceCount = Get-InstanceCount $Env
    
    Write-Status "Checking status for environment: $Env (namespace: $namespace)"
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
            Write-Host "$instanceName : $status (Ready: $ready)" -ForegroundColor $(if ($ready -eq "true") { "Green" } else { "Red" })
        } else {
            Write-Host "$instanceName : Not found" -ForegroundColor Red
        }
    }
}

# Scale instances
function Set-InstanceCount {
    param([string]$Env, [int]$Count)
    
    Write-Status "Scaling instances in $Env environment to $Count instances"
    
    # Update the helmfile values
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $helmfilePath = "$scriptDir/../helmfile"
    
    if ($Env -eq "dev") {
        $envFile = "$helmfilePath/environments/development/helmfile.yaml"
    } elseif ($Env -eq "prod") {
        $envFile = "$helmfilePath/environments/production/helmfile.yaml"
    } else {
        $envFile = "$helmfilePath/helmfile.yaml"
    }
    
    # Update the count in the helmfile
    $content = Get-Content $envFile -Raw
    $content = $content -replace "count: \d+", "count: $Count"
    Set-Content $envFile $content
    
    Write-Status "Updated helmfile configuration. Run 'helmfile apply' to apply changes."
}

# Get logs from specific instance
function Get-InstanceLogs {
    param([string]$Env, [int]$InstanceNumber)
    $namespace = Get-Namespace $Env
    $instanceName = "appender-java-{0:D2}" -f $InstanceNumber
    
    Write-Status "Getting logs for $instanceName in $Env environment"
    
    $podName = kubectl get pods -n $namespace --selector="app.kubernetes.io/instance=$instanceName" -o jsonpath="{.items[0].metadata.name}" 2>$null
    if ($podName) {
        kubectl logs $podName -n $namespace -f
    } else {
        Write-Error "Pod for instance $instanceName not found"
    }
}

# Restart specific instance
function Restart-Instance {
    param([string]$Env, [int]$InstanceNumber)
    $namespace = Get-Namespace $Env
    $instanceName = "appender-java-{0:D2}" -f $InstanceNumber
    
    Write-Status "Restarting $instanceName in $Env environment"
    
    kubectl rollout restart deployment/$instanceName -n $namespace
    kubectl rollout status deployment/$instanceName -n $namespace
}

# Check health of all instances
function Test-InstanceHealth {
    param([string]$Env)
    $namespace = Get-Namespace $Env
    $instanceCount = Get-InstanceCount $Env
    
    Write-Status "Checking health for all instances in $Env environment"
    Write-Host ""
    
    for ($i = 1; $i -le $instanceCount; $i++) {
        $instanceName = "appender-java-{0:D2}" -f $i
        $serviceName = "$instanceName-service"
        
        # Check if service exists
        $service = kubectl get service $serviceName -n $namespace 2>$null
        if ($service) {
            # Try to get the service port
            $port = kubectl get service $serviceName -n $namespace -o jsonpath="{.spec.ports[0].port}"
            
            Write-Host "Testing $instanceName on port $port..." -NoNewline
            
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
            Write-Host "$instanceName : Service not found" -ForegroundColor Red
        }
    }
}

# Main function
function Main {
    switch ($Command.ToLower()) {
        "status" {
            Show-InstanceStatus $Environment
        }
        "scale" {
            if ($InstanceCount -eq 0) {
                Write-Error "Please specify instance count: .\manage-instances.ps1 scale <env> <count>"
                exit 1
            }
            Set-InstanceCount $Environment $InstanceCount
        }
        "logs" {
            if ($InstanceNumber -eq 0) {
                Write-Error "Please specify instance number: .\manage-instances.ps1 logs <env> <instance-number>"
                exit 1
            }
            Get-InstanceLogs $Environment $InstanceNumber
        }
        "restart" {
            if ($InstanceNumber -eq 0) {
                Write-Error "Please specify instance number: .\manage-instances.ps1 restart <env> <instance-number>"
                exit 1
            }
            Restart-Instance $Environment $InstanceNumber
        }
        "health" {
            Test-InstanceHealth $Environment
        }
        "help" {
            Write-Host "Usage: .\manage-instances.ps1 [command] [environment] [options]"
            Write-Host ""
            Write-Host "Commands:"
            Write-Host "  status [env]     Show status of all instances (default: dev)"
            Write-Host "  scale [env] [n]  Scale to n instances (default: dev)"
            Write-Host "  logs [env] [n]   Get logs for instance n (default: dev)"
            Write-Host "  restart [env] [n] Restart instance n (default: dev)"
            Write-Host "  health [env]     Test health of all instances (default: dev)"
            Write-Host "  help             Show this help message"
            Write-Host ""
            Write-Host "Environments:"
            Write-Host "  dev              Development environment (3 instances)"
            Write-Host "  prod             Production environment (10 instances)"
            Write-Host ""
            Write-Host "Examples:"
            Write-Host "  .\manage-instances.ps1 status prod"
            Write-Host "  .\manage-instances.ps1 scale dev 5"
            Write-Host "  .\manage-instances.ps1 logs prod 3"
        }
        default {
            Write-Error "Unknown command: $Command"
            Write-Host "Run '.\manage-instances.ps1 help' for usage information"
            exit 1
        }
    }
}

# Run main function
Main 