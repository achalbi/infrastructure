# Local Deployment Setup for Observability Stack

This document describes the configuration for deploying the observability stack locally with filesystem storage.

## Overview

The observability stack has been configured for local deployment with the following components:
- **Loki**: Log aggregation with filesystem storage
- **Tempo**: Distributed tracing with local storage
- **Prometheus**: Metrics collection with local storage
- **Grafana**: Visualization and dashboards
- **OpenTelemetry Collector**: Telemetry data collection

## Configuration Changes Made

### 1. Loki Configuration (`value-files/loki/`)

#### Main Configuration (`values.yaml`)
- **Storage**: Configured for S3-compatible storage using MinIO
- **Deployment Mode**: Uses `SimpleScalable` mode for better performance and scalability
- **Components**:
  - **Backend**: 1 replica (handles storage and compaction)
  - **Read**: 1 replica (handles queries)
  - **Write**: 1 replica (handles ingestion)
- **Storage Configuration**: 
  - S3 endpoint: `http://loki-minio:9000`
  - Bucket: `loki`
  - Region: `us-east-1`
- **Retention**: 168 hours (7 days) for production-like testing
- **MinIO**: Enabled with 10Gi persistent storage

#### Development Overrides (`values.dev.yaml`)
- **Reduced Resources**: Lower memory and CPU limits for development
- **Shorter Retention**: 24 hours for development
- **Reduced Concurrency**: 2 concurrent queries instead of 4
- **Monitoring**: Disabled alerts, less frequent scraping
- **SimpleScalable Components**: Optimized resource allocation for development
- **MinIO**: Reduced resources (5Gi storage, lower CPU/memory limits)

#### Production Configuration (`values.prod.yaml`)
- **S3 Storage**: Configured for production S3 storage
- **Higher Resources**: Increased memory and CPU limits
- **Longer Retention**: 720 hours (30 days)
- **Scalable Deployment**: Uses `SimpleScalable` mode with multiple replicas

### 2. Tempo Configuration (`value-files/tempo/`)

#### Main Configuration (`values.yaml`)
- **Storage**: Local filesystem storage for traces
- **Trace Paths**:
  - Traces: `/var/tempo/traces`
  - WAL: `/var/tempo/wal`
- **Retention**: 1 hour block retention
- **OTLP Receivers**: Configured for gRPC (4317) and HTTP (4318)
- **Persistence**: 10Gi PVC for local storage

#### Development Overrides (`values.dev.yaml`)
- **Shorter Retention**: 30 minutes for development
- **Smaller Storage**: 5Gi PVC
- **Less Frequent Monitoring**: 60s scrape interval

### 3. OpenTelemetry Collector

The collector is already well-configured for local deployment:
- **Mode**: Deployment (single instance)
- **Exporters**: 
  - Loki for logs
  - Tempo for traces
  - Prometheus for metrics
- **Ports**: 
  - gRPC: 4317 (NodePort 30317)
  - HTTP: 4318 (NodePort 30318)

### 4. Grafana Configuration

- **Authentication**: Anonymous access enabled for local development
- **Datasources**: Pre-configured for Loki, Tempo, and Prometheus
- **Persistence**: Disabled (uses ephemeral storage)
- **Ingress**: Configured for local access

### 5. Prometheus Configuration

- **Storage**: 10Gi PVC for local storage
- **Remote Write**: Enabled for receiving metrics
- **Components**: Simplified for local deployment (disabled unnecessary components)

## Deployment Instructions

### Prerequisites
1. Kubernetes cluster (local or remote)
2. Helm 3.x
3. Helmfile
4. kubectl configured

### Deploy the Stack

1. **Navigate to the cluster directory**:
   ```bash
   cd cluster-o
   ```

2. **Deploy the entire stack**:
   ```bash
   helmfile apply
   ```

   Or deploy individual components:
   ```bash
   helmfile apply --selector name=loki
   helmfile apply --selector name=tempo
   helmfile apply --selector name=prometheus
   helmfile apply --selector name=grafana
   ```

### Access the Services

- **Grafana**: http://localhost:3000 (if using NodePort) or via ingress
- **Loki**: http://loki-gateway.observability:80
- **Tempo**: http://tempo.observability:3200
- **Prometheus**: http://prometheus-prometheus:9090

### Development vs Production

#### Development Environment
- Uses `values.dev.yaml` overrides
- Reduced resource requirements
- Shorter data retention
- Disabled alerts
- Less frequent monitoring

#### Production Environment
- Uses `values.prod.yaml` overrides
- S3 storage for persistence
- Higher resource limits
- Longer data retention
- Enabled alerts and monitoring

## Storage Considerations

### Local Development
- All data is stored in Kubernetes PVCs
- Data is ephemeral and will be lost on cluster restart
- Suitable for development and testing

### Production
- Use S3-compatible storage (AWS S3, MinIO, etc.)
- Configure proper backup strategies
- Consider data retention policies

## Troubleshooting

### Common Issues

1. **Storage Issues**:
   - Ensure PVCs are properly provisioned
   - Check storage class configuration
   - Verify volume mounts

2. **Resource Issues**:
   - Monitor resource usage with `kubectl top pods`
   - Adjust resource limits in value files
   - Consider reducing replica counts

3. **Network Issues**:
   - Verify service endpoints
   - Check ingress configuration
   - Ensure proper DNS resolution

### Useful Commands

```bash
# Check pod status
kubectl get pods -n observability

# Check PVC status
kubectl get pvc -n observability

# Check service endpoints
kubectl get svc -n observability

# View logs
kubectl logs -n observability deployment/loki
kubectl logs -n observability deployment/tempo
kubectl logs -n observability deployment/grafana
```

## Next Steps

1. Configure application instrumentation to send telemetry data
2. Set up custom dashboards in Grafana
3. Configure alerting rules for production
4. Implement proper backup and disaster recovery procedures 