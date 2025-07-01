# Multiple Instances Deployment Guide

This document describes how to deploy and manage multiple instances of the appender-java application using Helm templates and Helmfile.

## Overview

The multiple instances feature allows you to deploy multiple copies of the appender-java application with:
- Unique names (appender-java-01, appender-java-02, etc.)
- Unique ports (8080, 8081, 8082, etc.)
- Individual services for each instance
- Independent scaling and management
- **Chain-based communication**: Each instance targets the next instance in sequence

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                      │
├────────────────────────────────────────────────────────────┤
│  Namespace: {env}-appender-java                            │
│                                                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ appender-   │  │ appender-   │  │ appender-   │         │
│  │ java-01     │──│ java-02     │──│ java-03     │         │
│  │             │  │             │  │             │         │
│  │ Port: 8080  │  │ Port: 8081  │  │ Port: 8082  │         │
│  │ Target: 02  │  │ Target: 03  │  │ Target: 01  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                │                │                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ service-01  │  │ service-02  │  │ service-03  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

## Target URL Pattern

Each instance automatically targets the next instance in the sequence:

- **appender-java-01** → targets **appender-java-02**
- **appender-java-02** → targets **appender-java-03**
- **appender-java-03** → targets **appender-java-04**
- ...
- **appender-java-10** → targets **appender-java-01** (wraps around)

The target URL format is:
```
http://{next-instance-name}-service.{namespace}.svc.cluster.local:{next-instance-port}/append
```

Example for appender-java-01:
```
http://appender-java-02-service.dev-appender-java.svc.cluster.local:8081/append
```

## Configuration

### Values.yaml Configuration

```yaml
# Multiple instances configuration
instances:
  enabled: false          # Enable/disable multiple instances
  count: 10              # Number of instances to deploy
  namePattern: "appender-java-{index:02d}"  # Naming pattern
  basePort: 8080         # Base port for first instance
```

### Environment-Specific Configuration

#### Development Environment
```yaml
instances:
  enabled: true
  count: 3               # 3 instances for development
  namePattern: "appender-java-{index:02d}"
  basePort: 8080
```

#### Production Environment
```yaml
instances:
  enabled: true
  count: 10              # 10 instances for production
  namePattern: "appender-java-{index:02d}"
  basePort: 8080
```

## Deployment

### Using Helmfile

```bash
# Deploy to development environment
cd cluster-a/helmfile
helmfile -e development apply

# Deploy to production environment
helmfile -e production apply
```

### Using ArgoCD

The ArgoCD applications will automatically deploy multiple instances based on the configuration in the Git repository.

## Instance Management

### PowerShell Management Script

Use the provided PowerShell script to manage instances:

```powershell
# Show status of all instances
.\scripts\manage-instances.ps1 status dev

# Scale instances
.\scripts\manage-instances.ps1 scale dev 5

# Get logs from specific instance
.\scripts\manage-instances.ps1 logs dev 3

# Restart specific instance
.\scripts\manage-instances.ps1 restart dev 3

# Check health of all instances
.\scripts\manage-instances.ps1 health dev
```

### Bash Management Script

Use the provided Bash script to manage instances:

```bash
# Show status of all instances
./scripts/manage-instances.sh status dev

# Scale instances
./scripts/manage-instances.sh scale dev 5

# Get logs from specific instance
./scripts/manage-instances.sh logs dev 3

# Restart specific instance
./scripts/manage-instances.sh restart dev 3

# Check health of all instances
./scripts/manage-instances.sh health dev
```

### Manual kubectl Commands

```bash
# List all deployments
kubectl get deployments -n dev-appender-java

# List all services
kubectl get services -n dev-appender-java

# Get logs from specific instance
kubectl logs -n dev-appender-java deployment/appender-java-01

# Scale specific instance
kubectl scale deployment appender-java-01 -n dev-appender-java --replicas=2

# Check instance health
kubectl get pods -n dev-appender-java --selector=app.kubernetes.io/name=appender-java

# Check target URL for specific instance
kubectl get pod -n dev-appender-java -l app.kubernetes.io/instance=appender-java-01 -o jsonpath='{.spec.containers[0].env[?(@.name=="TARGET_URL")].value}'

# Check node type for specific instance
kubectl get pod -n dev-appender-java -l app.kubernetes.io/instance=appender-java-01 -o jsonpath='{.spec.containers[0].env[?(@.name=="NODE_TYPE")].value}'

# Verify all target URLs and node types
for i in {01..03}; do
  echo "appender-java-$i:"
  echo "  NODE_TYPE: $(kubectl get pod -n dev-appender-java -l app.kubernetes.io/instance=appender-java-$i -o jsonpath='{.spec.containers[0].env[?(@.name=="NODE_TYPE")].value}' 2>/dev/null)"
  echo "  TARGET_URL: $(kubectl get pod -n dev-appender-java -l app.kubernetes.io/instance=appender-java-$i -o jsonpath='{.spec.containers[0].env[?(@.name=="TARGET_URL")].value}' 2>/dev/null)"
  echo
done
```

## Instance Details

### Generated Resources

For each instance, the following resources are created:

1. **Deployment**: `appender-java-{index}`
   - Unique pod labels
   - Instance-specific environment variables
   - Individual port configuration
   - Dynamic target URL pointing to next instance

2. **Service**: `appender-java-{index}-service`
   - Unique port mapping
   - Instance-specific selectors

### Environment Variables

Each instance receives these environment variables:
- `POD_NAME`: Kubernetes pod name
- `INSTANCE_INDEX`: Instance number (1, 2, 3, etc.)
- `INSTANCE_NAME`: Instance name (appender-java-01, etc.)
- `NODE_TYPE`: **Node type in the chain** - "begin" (first), "link" (middle), or "end" (last)
- `TARGET_URL`: **Dynamically generated** URL pointing to the next instance (not present for last instance)

### Node Types

The chain has three types of nodes:

1. **Begin Node** (First Instance):
   - `NODE_TYPE`: "begin"
   - `TARGET_URL`: Points to second instance
   - Example: appender-java-01

2. **Link Nodes** (Middle Instances):
   - `NODE_TYPE`: "link"
   - `TARGET_URL`: Points to next instance
   - Example: appender-java-02 through appender-java-09

3. **End Node** (Last Instance):
   - `NODE_TYPE`: "end"
   - `TARGET_URL`: **Not present** (end of chain)
   - Example: appender-java-10

### Port Allocation

Ports are allocated sequentially starting from the base port:
- Instance 1: Port 8080
- Instance 2: Port 8081
- Instance 3: Port 8082
- ... and so on

### Target URL Examples

For a 3-instance development setup:
- **appender-java-01** (begin): `http://appender-java-02-service.dev-appender-java.svc.cluster.local:8081/append`
- **appender-java-02** (link): `http://appender-java-03-service.dev-appender-java.svc.cluster.local:8082/append`
- **appender-java-03** (end): No TARGET_URL

For a 10-instance production setup:
- **appender-java-01** (begin): `http://appender-java-02-service.prod-appender-java.svc.cluster.local:8081/append`
- **appender-java-02** (link): `http://appender-java-03-service.prod-appender-java.svc.cluster.local:8082/append`
- **appender-java-03** (link): `http://appender-java-04-service.prod-appender-java.svc.cluster.local:8083/append`
- ...
- **appender-java-09** (link): `http://appender-java-10-service.prod-appender-java.svc.cluster.local:8089/append`
- **appender-java-10** (end): No TARGET_URL

## Monitoring and Observability

### Health Checks

Each instance has independent health checks:
- **Liveness Probe**: `/actuator/health/liveness`
- **Readiness Probe**: `/actuator/health/readiness`

### Metrics and Logging

- Each instance generates its own logs
- Metrics are tagged with instance information
- Prometheus can scrape metrics from each instance

### Service Discovery

Services can be discovered using:
```bash
# Get service endpoints
kubectl get endpoints -n dev-appender-java

# Port forward to specific instance
kubectl port-forward service/appender-java-01-service 8080:8080 -n dev-appender-java

# Test the chain by following the target URLs
kubectl exec -n dev-appender-java deployment/appender-java-01 -- curl -s $TARGET_URL
```

## Scaling Strategies

### Horizontal Scaling

1. **Instance-Level Scaling**: Increase the number of instances
2. **Pod-Level Scaling**: Scale replicas within each instance

### Configuration Updates

```yaml
# Scale to 15 instances
instances:
  enabled: true
  count: 15

# Apply changes
helmfile apply
```

## Troubleshooting

### Common Issues

#### 1. Port Conflicts
**Problem**: Multiple instances trying to use the same port
**Solution**: Ensure `basePort` is set correctly and ports don't overlap

#### 2. Resource Limits
**Problem**: Cluster doesn't have enough resources for all instances
**Solution**: 
- Reduce instance count
- Adjust resource limits in values.yaml
- Scale down other workloads

#### 3. Service Discovery Issues
**Problem**: Services can't find each other
**Solution**: Use the correct service names: `appender-java-{index}-service`

#### 4. Target URL Issues
**Problem**: Instances can't reach their target
**Solution**: 
- Verify the target service exists
- Check network policies
- Ensure the target endpoint is available

### Debugging Commands

```bash
# Check all instances status
kubectl get all -n dev-appender-java

# Check events
kubectl get events -n dev-appender-java --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n dev-appender-java

# Check service endpoints
kubectl get endpoints -n dev-appender-java

# Verify target URLs
for i in {01..03}; do
  echo "appender-java-$i:"
  echo "  NODE_TYPE: $(kubectl get pod -n dev-appender-java -l app.kubernetes.io/instance=appender-java-$i -o jsonpath='{.spec.containers[0].env[?(@.name=="NODE_TYPE")].value}' 2>/dev/null)"
  echo "  TARGET_URL: $(kubectl get pod -n dev-appender-java -l app.kubernetes.io/instance=appender-java-$i -o jsonpath='{.spec.containers[0].env[?(@.name=="TARGET_URL")].value}' 2>/dev/null)"
  echo
done
```

## Best Practices

### 1. Resource Management
- Set appropriate resource limits for each instance
- Monitor resource usage across all instances
- Use horizontal pod autoscaling when appropriate

### 2. Configuration Management
- Use environment-specific configurations
- Version control all configuration changes
- Use GitOps for deployment automation

### 3. Monitoring
- Set up alerts for instance failures
- Monitor aggregate metrics across all instances
- Use distributed tracing for request flows
- Monitor the chain of requests across instances

### 4. Security
- Use network policies to restrict inter-instance communication
- Implement proper RBAC for instance management
- Secure service-to-service communication

### 5. Chain Management
- Monitor the health of the entire chain
- Implement circuit breakers for fault tolerance
- Consider load balancing across the chain
- Test chain integrity regularly

## Migration from Single Instance

### Step 1: Backup Current Configuration
```bash
# Backup current deployment
kubectl get deployment appender-java -n appender-java -o yaml > backup.yaml
```

### Step 2: Enable Multiple Instances
```yaml
# Update values.yaml
instances:
  enabled: true
  count: 3  # Start with a small number
```

### Step 3: Deploy and Test
```bash
# Deploy multiple instances
helmfile apply

# Verify all instances are running
kubectl get pods -n dev-appender-java

# Test the chain
kubectl exec -n dev-appender-java deployment/appender-java-01 -- curl -s $TARGET_URL
```

### Step 4: Scale Up
```yaml
# Increase instance count
instances:
  count: 10
```

## Performance Considerations

### Load Balancing
- Use a load balancer to distribute traffic across instances
- Consider using Kubernetes Ingress for HTTP traffic
- Implement client-side load balancing for service-to-service calls

### Resource Optimization
- Monitor CPU and memory usage per instance
- Adjust resource limits based on actual usage
- Consider using node affinity for better resource distribution

### Network Optimization
- Use service mesh for advanced traffic management
- Implement circuit breakers for fault tolerance
- Monitor network latency between instances

### Chain Performance
- Monitor end-to-end latency through the chain
- Implement caching strategies
- Consider parallel processing where possible

## Future Enhancements

### Planned Features
1. **Auto-scaling**: Automatic instance scaling based on metrics
2. **Blue-green deployment**: Zero-downtime instance updates
3. **Instance groups**: Logical grouping of instances
4. **Advanced monitoring**: Instance-specific dashboards
5. **Chain visualization**: Visual representation of the instance chain
6. **Dynamic routing**: Configurable routing patterns

### Integration Opportunities
1. **Service Mesh**: Istio or Linkerd integration
2. **API Gateway**: Kong or Ambassador integration
3. **Observability**: Jaeger, Zipkin, or OpenTelemetry
4. **Security**: mTLS and service-to-service authentication
5. **Message Queues**: Kafka or RabbitMQ for async communication 