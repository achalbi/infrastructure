# Network Connectivity Troubleshooting Guide

## Common Network Issues and Solutions

### 1. Loki Connection Timeout

**Error Message:**
```
timeout tailing new logs (timeout period: 10.00s), will retry in 10 seconds: read tcp 10.244.2.9:45262->10.96.39.195:80: i/o timeout
```

**Causes:**
- Network connectivity issues between pods
- Service endpoint problems
- Resource constraints causing slow responses
- DNS resolution issues
- Firewall or network policy blocking connections

**Solutions Applied:**

#### A. Enhanced Service Configuration
```yaml
service:
  type: ClusterIP
  port: 80
  targetPort: 3100
  annotations: {}

gateway:
  enabled: true
  replicas: 1
  service:
    type: ClusterIP
    port: 80
    targetPort: 80
```

#### B. Improved Server Timeouts
```yaml
server:
  http_listen_port: 3100
  grpc_listen_port: 9095
  http_server_read_timeout: 5m
  http_server_write_timeout: 5m
  http_server_idle_timeout: 120s
```

#### C. Resource Allocation
```yaml
singleBinary:
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"
```

### 2. Diagnostic Commands

#### Check Service Status
```bash
# Check if Loki services are running
kubectl get svc -n observability | grep loki

# Check service endpoints
kubectl get endpoints -n observability | grep loki

# Check if pods are ready
kubectl get pods -n observability -l app.kubernetes.io/name=loki
```

#### Test Network Connectivity
```bash
# Test connectivity from within the cluster
kubectl run test-connectivity --image=busybox --rm -it --restart=Never -- nslookup loki-gateway.observability.svc.cluster.local

# Test HTTP connectivity
kubectl run test-http --image=curlimages/curl --rm -it --restart=Never -- curl -v http://loki-gateway.observability.svc.cluster.local:80/ready

# Test from a specific pod
kubectl exec -n observability deployment/loki -- curl -s http://localhost:3100/ready
```

#### Check DNS Resolution
```bash
# Check DNS resolution
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup loki-gateway.observability.svc.cluster.local

# Check CoreDNS logs
kubectl logs -n kube-system deployment/coredns
```

### 3. Network Policy Issues

#### Check Network Policies
```bash
# List network policies
kubectl get networkpolicies --all-namespaces

# Check if network policies are blocking traffic
kubectl describe networkpolicy -n observability
```

#### Common Network Policy Fixes
```yaml
# Allow Loki traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-loki-traffic
  namespace: observability
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: loki
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 3100
    - protocol: TCP
      port: 80
```

### 4. Resource Monitoring

#### Check Resource Usage
```bash
# Check pod resource usage
kubectl top pods -n observability

# Check node resource usage
kubectl top nodes

# Check if pods are being evicted
kubectl get events -n observability --sort-by='.lastTimestamp'
```

#### Memory and CPU Issues
```bash
# Check Loki memory usage
kubectl exec -n observability deployment/loki -- cat /proc/meminfo

# Check Loki CPU usage
kubectl exec -n observability deployment/loki -- top -n 1
```

### 5. Service Discovery Issues

#### Check Service Endpoints
```bash
# Verify service endpoints
kubectl get endpoints loki-gateway -n observability

# Check if endpoints are properly configured
kubectl describe svc loki-gateway -n observability
```

#### DNS Issues
```bash
# Test DNS from different namespaces
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup loki-gateway.observability.svc.cluster.local

# Check CoreDNS configuration
kubectl get configmap coredns -n kube-system -o yaml
```

### 6. Port Forwarding for Testing

#### Test Direct Access
```bash
# Port forward to Loki service
kubectl port-forward -n observability svc/loki-gateway 8080:80

# Test in another terminal
curl http://localhost:8080/ready

# Test tail endpoint
curl "http://localhost:8080/loki/api/v1/tail?query={stream=\"stdout\"}"
```

### 7. Log Analysis

#### Check Loki Logs
```bash
# Check Loki application logs
kubectl logs -n observability deployment/loki -f

# Check Loki gateway logs
kubectl logs -n observability deployment/loki-gateway -f

# Check for error patterns
kubectl logs -n observability deployment/loki | grep -i error
```

#### Check System Logs
```bash
# Check kubelet logs
kubectl logs -n kube-system daemonset/kube-proxy

# Check CoreDNS logs
kubectl logs -n kube-system deployment/coredns
```

### 8. Configuration Validation

#### Validate Loki Configuration
```bash
# Check if Loki config is valid
kubectl exec -n observability deployment/loki -- loki --config.file=/etc/loki/config/config.yaml --dry-run

# Check configuration file
kubectl exec -n observability deployment/loki -- cat /etc/loki/config/config.yaml
```

### 9. Performance Optimization

#### Network Performance
```yaml
# Optimize for network performance
server:
  http_server_read_timeout: 5m
  http_server_write_timeout: 5m
  http_server_idle_timeout: 120s

# Increase connection limits
limits_config:
  max_concurrent: 32
  max_streams_per_user: 0
```

#### Resource Optimization
```yaml
# Ensure adequate resources
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

### 10. Common Solutions

#### Quick Fixes to Try

1. **Restart Loki:**
   ```bash
   kubectl rollout restart deployment/loki -n observability
   ```

2. **Check and fix service endpoints:**
   ```bash
   kubectl get endpoints -n observability
   kubectl delete endpoints loki-gateway -n observability
   kubectl get endpoints -n observability
   ```

3. **Verify namespace isolation:**
   ```bash
   kubectl get networkpolicies --all-namespaces
   ```

4. **Test with different client:**
   ```bash
   kubectl run test-client --image=curlimages/curl --rm -it --restart=Never -- curl -v http://loki-gateway.observability.svc.cluster.local:80/ready
   ```

### 11. Monitoring and Alerting

#### Key Metrics to Monitor
- `loki_request_duration_seconds`: Request latency
- `loki_request_errors_total`: Error count
- `loki_ingester_memory_chunks`: Memory usage
- `loki_querier_request_duration_seconds`: Query performance

#### Set up alerts for:
- High request latency (>5s)
- High error rates (>5%)
- Memory usage >80%
- Service endpoint failures 