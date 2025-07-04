# Loki Troubleshooting Guide

## Common Issues and Solutions

### 1. "failed to find entry" Error

**Error Message:**
```
failed to find entry 1751656861377947871 in Loki when spot check querying 56m59.001636715s after it was written
```

**Causes:**
- Chunk lifecycle issues (chunks not being flushed properly)
- Query consistency problems
- Cache freshness issues
- Ingest/query timing mismatches

**Solutions Applied:**

#### A. Improved Chunk Lifecycle Management
```yaml
ingester:
  chunk_idle_period: 30m        # Reduced from 2h
  max_chunk_age: 30m            # Reduced from 2h

chunk_retain_period: 30s      # Added for better consistency
```

#### B. Enhanced Query Configuration
```yaml
querier:
  max_concurrent: 4             # Optimized concurrency
```

#### C. Query Range Configuration
```yaml
query_range:
  align_queries_with_step: true
  max_retries: 5
  cache_results: true
  results_cache:
    cache:
      enable_fifocache: true
      validity: 24h
```

#### D. Improved Cache and Limits
```yaml
limits_config:
  max_cache_freshness_per_query: 1m  # Reduced from 10m
  max_query_parallelism: 32          # Added parallelism
  max_streams_per_user: 0            # Unlimited streams
  max_global_streams_per_user: 0     # Unlimited global streams
  max_query_length: 721h             # Extended query length
```

#### E. Faster Compaction
```yaml
compactor:
  compaction_interval: 5m       # Reduced from 10m
  retention_delete_delay: 1h    # Reduced from 2h
```

#### F. Enhanced Storage Configuration
```yaml
storage_config:
  tsdb_shipper:
    cache_ttl: 24h              # Cache TTL for better performance
```

### 2. Development-Specific Optimizations

For development environments, use even faster settings:

```yaml
# In values.dev.yaml
loki:
  limits_config:
    max_cache_freshness_per_query: 30s  # Very fast cache refresh
  
  querier:
    max_concurrent: 2                   # Reduced concurrency
  
  ingester:
    chunk_idle_period: 15m              # Faster chunk flushing
    max_chunk_age: 15m                  # Faster chunk aging
    chunk_retain_period: 15s            # Shorter retention
  
  query_range:
    max_retries: 3                      # Fewer retries
    cache_results: true                 # Enable caching
```

### 3. Verification Steps

After applying changes, verify the configuration:

```bash
# Check Loki pod status
kubectl get pods -n observability -l app.kubernetes.io/name=loki

# Check Loki logs for errors
kubectl logs -n observability deployment/loki -f

# Test Loki health
kubectl exec -n observability deployment/loki -- curl -s http://localhost:3100/ready

# Check Loki metrics
kubectl exec -n observability deployment/loki -- curl -s http://localhost:3100/metrics | grep -E "(loki_ingester|loki_querier)"
```

### 4. Additional Debugging Commands

```bash
# Check chunk status
kubectl exec -n observability deployment/loki -- ls -la /var/loki/chunks/

# Check TSDB index status
kubectl exec -n observability deployment/loki -- ls -la /data/tsdb-index/

# Check Loki configuration
kubectl exec -n observability deployment/loki -- cat /etc/loki/loki.yaml

# Monitor Loki metrics
kubectl port-forward -n observability svc/loki-gateway 3100:80
# Then visit http://localhost:3100/metrics
```

### 5. Performance Monitoring

Key metrics to monitor:

- `loki_ingester_memory_chunks`: Number of chunks in memory
- `loki_ingester_chunk_utilization`: Chunk utilization ratio
- `loki_querier_request_duration_seconds`: Query response times
- `loki_compactor_compaction_duration_seconds`: Compaction duration
- `loki_ingester_chunk_flush_duration_seconds`: Chunk flush duration

### 6. When to Restart Loki

Restart Loki if you see:
- Persistent "failed to find entry" errors
- High memory usage with stuck chunks
- Configuration changes not taking effect

```bash
kubectl rollout restart deployment/loki -n observability
```

### 7. Data Consistency Best Practices

1. **Use appropriate chunk settings** for your workload
2. **Monitor chunk lifecycle** metrics
3. **Set reasonable timeouts** for queries
4. **Enable proper logging** for debugging
5. **Use development settings** for local testing
6. **Monitor resource usage** to prevent OOM issues

### 8. Query Optimization

For better query performance:

```logql
# Use specific label selectors
{app="myapp", pod=~"myapp-.*"}

# Avoid regex on high-cardinality labels
# Bad: {pod=~".*"}
# Good: {pod="specific-pod-name"}

# Use time range limits
{app="myapp"}[5m]

# Use rate() for high-volume logs
rate({app="myapp"}[1m])
```

### 9. Resource Recommendations

For local development:
- **Memory**: 512Mi-1Gi
- **CPU**: 500m-1000m
- **Storage**: 10Gi minimum

For production:
- **Memory**: 2Gi-4Gi per replica
- **CPU**: 1000m-2000m per replica
- **Storage**: 50Gi+ with proper backup strategy 