# Complete Guide: Deploying LLMs with llama.cpp on OpenShift

This guide provides step-by-step instructions for deploying large language models using llama.cpp on OpenShift, including both CPU and GPU configurations. It includes all lessons learned and pitfalls to avoid.

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture Decisions](#architecture-decisions)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Common Pitfalls and Solutions](#common-pitfalls-and-solutions)
6. [Testing and Validation](#testing-and-validation)
7. [Performance Comparison](#performance-comparison)
8. [Troubleshooting](#troubleshooting)

## Overview

This deployment creates:
- A namespace for isolation
- Persistent storage for the model (using ReadWriteMany PVC)
- CPU-based deployment for baseline performance
- GPU-based deployment for accelerated inference (optional)
- Separate services and routes for each deployment
- Web UI and API endpoints for interaction

**Key Technologies:**
- **llama.cpp**: Efficient LLM inference engine with CPU and CUDA support
- **GGUF format**: Quantized model format for reduced memory footprint
- **OpenShift**: Kubernetes-based container platform
- **OpenShift AI**: Optional, provides GPU resources and monitoring

## Prerequisites

### Required
- OpenShift cluster access with `oc` CLI configured
- Permissions to create namespaces, deployments, services, routes, and PVCs
- Storage class that supports ReadWriteMany (RWX) access mode (e.g., CephFS, NFS)
- Internet access from cluster to download models (or pre-downloaded models)

### Optional (for GPU acceleration)
- OpenShift AI installed on cluster
- Available GPU resources (NVIDIA GPUs with CUDA support)
- GPU operator configured

### Verify Prerequisites
```bash
# Check cluster access
oc whoami
oc version

# Check available storage classes
oc get storageclass

# Check for GPU nodes (if using GPU)
oc get nodes -l nvidia.com/gpu.present=true

# Check OpenShift AI installation (if applicable)
oc get pods -n redhat-ods-operator
```

## Architecture Decisions

### 1. Model Selection
**Recommendation**: Start with Mistral 7B Instruct v0.2 (Q4_K_M quantization)
- **Size**: ~4GB (fits in most GPU memory configurations)
- **Quality**: Good balance of performance and accuracy
- **Format**: GGUF with Q4_K_M quantization

**Alternative Models**:
- Smaller: TinyLlama 1.1B (~600MB)
- Larger: Mixtral 8x7B (~26GB), Llama 2 13B (~7GB)
- Different quantization: Q5_K_M (better quality, larger), Q3_K_M (smaller, lower quality)

**Model Sources**:
- Hugging Face: https://huggingface.co/TheBloke
- Direct download: Use wget/curl in init container

### 2. Storage Strategy
**Critical Decision**: Use ReadWriteMany (RWX) PVC from the start

**Why RWX?**
- Allows multiple pods to mount the same volume simultaneously
- Essential if you want both CPU and GPU deployments sharing the same model
- Enables easy scaling and updates

**Storage Classes**:
- ✅ CephFS (RWX supported)
- ✅ NFS (RWX supported)
- ❌ AWS EBS, Azure Disk (RWO only - won't work for multiple pods)

**Pitfall to Avoid**: Don't start with ReadWriteOnce (RWO) if you plan to have multiple deployments. Migration requires creating a new PVC and copying data.

### 3. Image Selection
**Recommended Images**:
- CPU: `ghcr.io/ggml-org/llama.cpp:server`
- GPU: `ghcr.io/ggml-org/llama.cpp:server-cuda`

**Pitfall to Avoid**: Don't use `:latest` or `:light` tags - they may not include the server binary. Use `:server` or `:server-cuda` specifically.

### 4. Service Selector Strategy
**Critical**: Use unique labels for each deployment type

**Correct Approach**:
```yaml
# CPU Deployment
metadata:
  labels:
    app: llama-cpp
    component: server
    accelerator: cpu  # ← Critical for proper routing

# GPU Deployment  
metadata:
  labels:
    app: llama-cpp
    component: server
    accelerator: gpu  # ← Critical for proper routing
```

**Pitfall to Avoid**: Without the `accelerator` label, services with overlapping selectors will route to random pods, causing intermittent failures.

## Step-by-Step Deployment

### Step 1: Create Namespace
```bash
# Create namespace
oc create namespace <your-namespace>

# Set as current context
oc project <your-namespace>
```

Or use manifest:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <your-namespace>
  labels:
    app: llama-cpp
```

### Step 2: Create PVC with RWX Access Mode
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-storage-rwx
  namespace: <your-namespace>
spec:
  accessModes:
    - ReadWriteMany  # ← Critical for multiple pods
  resources:
    requests:
      storage: 30Gi  # Adjust based on model size
  storageClassName: ocs-storagecluster-cephfs  # ← Use your RWX storage class
```

**Important**: Replace `ocs-storagecluster-cephfs` with your cluster's RWX storage class name.

### Step 3: Create ConfigMap for Server Configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: llama-cpp-config
  namespace: <your-namespace>
data:
  MODEL_URL: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
  MODEL_NAME: "mistral-7b-instruct-v0.2.Q4_K_M.gguf"
  CONTEXT_SIZE: "4096"
  GPU_LAYERS: "35"  # For GPU deployment
```

**Customization**:
- Change `MODEL_URL` to your preferred model
- Adjust `CONTEXT_SIZE` based on your needs (higher = more memory)
- Set `GPU_LAYERS` to 0 for CPU-only, or number of layers for GPU

### Step 4: Create CPU Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-cpp-server
  namespace: <your-namespace>
  labels:
    app: llama-cpp
    component: server
    accelerator: cpu  # ← Important for service routing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-cpp
      component: server
      accelerator: cpu
  template:
    metadata:
      labels:
        app: llama-cpp
        component: server
        accelerator: cpu  # ← Must match selector
        model: mistral-7b
    spec:
      initContainers:
      - name: model-downloader
        image: curlimages/curl:latest
        command:
        - sh
        - -c
        - |
          if [ ! -f /models/${MODEL_NAME} ]; then
            echo "Downloading model..."
            curl -L -o /models/${MODEL_NAME} ${MODEL_URL}
            echo "Download complete"
          else
            echo "Model already exists, skipping download"
          fi
        env:
        - name: MODEL_URL
          valueFrom:
            configMapKeyRef:
              name: llama-cpp-config
              key: MODEL_URL
        - name: MODEL_NAME
          valueFrom:
            configMapKeyRef:
              name: llama-cpp-config
              key: MODEL_NAME
        volumeMounts:
        - name: model-storage
          mountPath: /models
      containers:
      - name: llama-cpp-server
        image: ghcr.io/ggml-org/llama.cpp:server
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        - name: MODEL_NAME
          valueFrom:
            configMapKeyRef:
              name: llama-cpp-config
              key: MODEL_NAME
        - name: CONTEXT_SIZE
          valueFrom:
            configMapKeyRef:
              name: llama-cpp-config
              key: CONTEXT_SIZE
        args:
        - "-m"
        - "/models/$(MODEL_NAME)"
        - "--host"
        - "0.0.0.0"
        - "--port"
        - "8080"
        - "-c"
        - "$(CONTEXT_SIZE)"
        - "--n-gpu-layers"
        - "0"  # CPU only
        volumeMounts:
        - name: model-storage
          mountPath: /models
        resources:
          requests:
            memory: "8Gi"
            cpu: "2"
          limits:
            memory: "16Gi"
            cpu: "4"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: model-storage-rwx
```

### Step 5: Create CPU Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: llama-cpp-service
  namespace: <your-namespace>
  labels:
    app: llama-cpp
    component: service
    accelerator: cpu
spec:
  selector:
    app: llama-cpp
    component: server
    accelerator: cpu  # ← Must match deployment labels
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
```

### Step 6: Create CPU Route
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: llama-cpp-route
  namespace: <your-namespace>
  labels:
    app: llama-cpp
    component: route
    accelerator: cpu
  annotations:
    haproxy.router.openshift.io/timeout: 3h
    haproxy.router.openshift.io/balance: source
spec:
  to:
    kind: Service
    name: llama-cpp-service
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

### Step 7: Create GPU Deployment (Optional)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-cpp-server-gpu
  namespace: <your-namespace>
  labels:
    app: llama-cpp
    component: server
    accelerator: gpu  # ← Important for service routing
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-cpp
      component: server
      accelerator: gpu
  template:
    metadata:
      labels:
        app: llama-cpp
        component: server
        accelerator: gpu  # ← Must match selector
        model: mistral-7b
    spec:
      containers:
      - name: llama-cpp-server
        image: ghcr.io/ggml-org/llama.cpp:server-cuda  # ← CUDA-enabled image
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        - name: MODEL_NAME
          valueFrom:
            configMapKeyRef:
              name: llama-cpp-config
              key: MODEL_NAME
        - name: CONTEXT_SIZE
          valueFrom:
            configMapKeyRef:
              name: llama-cpp-config
              key: CONTEXT_SIZE
        - name: GPU_LAYERS
          valueFrom:
            configMapKeyRef:
              name: llama-cpp-config
              key: GPU_LAYERS
        args:
        - "-m"
        - "/models/$(MODEL_NAME)"
        - "--host"
        - "0.0.0.0"
        - "--port"
        - "8080"
        - "-c"
        - "$(CONTEXT_SIZE)"
        - "--n-gpu-layers"
        - "$(GPU_LAYERS)"  # Use GPU acceleration
        volumeMounts:
        - name: model-storage
          mountPath: /models
        resources:
          requests:
            memory: "8Gi"
            nvidia.com/gpu: 1  # Request 1 GPU
          limits:
            memory: "16Gi"
            nvidia.com/gpu: 1
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: model-storage-rwx  # ← Same PVC as CPU deployment
```

### Step 8: Create GPU Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: llama-cpp-service-gpu
  namespace: <your-namespace>
  labels:
    app: llama-cpp
    component: service
    accelerator: gpu
spec:
  selector:
    app: llama-cpp
    component: server
    accelerator: gpu  # ← Must match GPU deployment labels
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
```

### Step 9: Create GPU Route
```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: llama-cpp-route-gpu
  namespace: <your-namespace>
  labels:
    app: llama-cpp
    component: route
    accelerator: gpu
  annotations:
    haproxy.router.openshift.io/timeout: 3h
    haproxy.router.openshift.io/balance: source
spec:
  to:
    kind: Service
    name: llama-cpp-service-gpu
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

### Step 10: Deploy Everything
```bash
# Apply all manifests
oc apply -f k8s-manifests/

# Or apply individually in order
oc apply -f k8s-manifests/01-namespace.yaml
oc apply -f k8s-manifests/02-pvc-rwx.yaml
oc apply -f k8s-manifests/03-configmap.yaml
oc apply -f k8s-manifests/04-deployment-cpu-only.yaml
oc apply -f k8s-manifests/05-service.yaml
oc apply -f k8s-manifests/06-route.yaml
oc apply -f k8s-manifests/07-deployment-gpu.yaml  # Optional
oc apply -f k8s-manifests/08-service-gpu.yaml     # Optional
oc apply -f k8s-manifests/09-route-gpu.yaml       # Optional
```

## Common Pitfalls and Solutions

### Pitfall 1: Using ReadWriteOnce (RWO) PVC
**Problem**: Cannot mount the same PVC to multiple pods (CPU and GPU deployments).

**Symptoms**:
- Second deployment fails to start
- Error: "Multi-Attach error for volume"

**Solution**:
- Use ReadWriteMany (RWX) storage class from the start
- If already using RWO, create new RWX PVC and copy data:

```yaml
# Create copy job
apiVersion: batch/v1
kind: Job
metadata:
  name: copy-model-to-rwx
spec:
  template:
    spec:
      containers:
      - name: copy
        image: busybox
        command: ['sh', '-c', 'cp -r /source/* /dest/']
        volumeMounts:
        - name: source
          mountPath: /source
        - name: dest
          mountPath: /dest
      volumes:
      - name: source
        persistentVolumeClaim:
          claimName: old-rwo-pvc
      - name: dest
        persistentVolumeClaim:
          claimName: new-rwx-pvc
      restartPolicy: Never
```

### Pitfall 2: Wrong llama.cpp Image Tag
**Problem**: Using `:latest` or `:light` tags that don't include the server binary.

**Symptoms**:
- Pod crashes with "server: command not found"
- CrashLoopBackOff status

**Solution**:
- Use specific tags: `:server` for CPU, `:server-cuda` for GPU
- Verify image contents: `oc run test --image=ghcr.io/ggml-org/llama.cpp:server --rm -it -- ls /app`

### Pitfall 3: Overlapping Service Selectors
**Problem**: Services select pods from multiple deployments due to missing labels.

**Symptoms**:
- Intermittent connection failures
- Requests sometimes work, sometimes timeout
- Wrong deployment responding to requests

**Solution**:
- Add unique `accelerator` label to each deployment
- Include `accelerator` in service selectors
- Verify with: `oc get endpoints -n your-namespace`

### Pitfall 4: Insufficient GPU Layers Configuration
**Problem**: GPU deployment not using GPU effectively.

**Symptoms**:
- GPU deployment no faster than CPU
- Low GPU utilization

**Solution**:
- Set `--n-gpu-layers` to appropriate value (35 for Mistral 7B)
- Check GPU usage: `oc exec -it <gpu-pod> -- nvidia-smi`
- Adjust based on model size and GPU memory

### Pitfall 5: Inadequate Resource Limits
**Problem**: Pod OOMKilled or evicted due to insufficient memory.

**Symptoms**:
- Pod status: OOMKilled
- Frequent restarts
- Slow inference

**Solution**:
- Set appropriate memory limits based on model size:
  - 7B model: 8-16Gi
  - 13B model: 16-32Gi
  - 70B model: 64Gi+
- Monitor actual usage: `oc adm top pods`

### Pitfall 6: Model Download Timeout
**Problem**: Init container times out downloading large models.

**Symptoms**:
- Init container fails
- "context deadline exceeded" error

**Solution**:
- Increase init container timeout
- Use faster mirror or CDN
- Pre-download model and use PVC initialization
- Add retry logic to download script

### Pitfall 7: Route Timeout for Long Requests
**Problem**: Route times out during long inference requests.

**Symptoms**:
- 504 Gateway Timeout
- Works for short prompts, fails for long ones

**Solution**:
- Add route annotation: `haproxy.router.openshift.io/timeout: 3h`
- Adjust based on expected inference time

## Testing and Validation

### 1. Check Pod Status
```bash
# View all pods
oc get pods -n <your-namespace>

# Check specific pod logs
oc logs -f deployment/llama-cpp-server -n <your-namespace>
oc logs -f deployment/llama-cpp-server-gpu -n <your-namespace>

# Describe pod for events
oc describe pod <pod-name>
```

### 2. Verify Service Endpoints
```bash
# Check service endpoints
oc get endpoints -n <your-namespace>

# Should show different IPs for CPU and GPU services
# CPU service should only point to CPU pod
# GPU service should only point to GPU pod
```

### 3. Test from Within Cluster
```bash
# Test CPU service
oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never \
  -- curl -sS http://llama-cpp-service:8080/v1/models

# Test GPU service
oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never \
  -- curl -sS http://llama-cpp-service-gpu:8080/v1/models
```

### 4. Test External Routes
```bash
# Get route URLs
oc get routes -n <your-namespace>

# Test CPU route
CPU_ROUTE=$(oc get route llama-cpp-route -o jsonpath='{.spec.host}')
curl https://${CPU_ROUTE}/v1/models

# Test GPU route
GPU_ROUTE=$(oc get route llama-cpp-route-gpu -o jsonpath='{.spec.host}')
curl https://${GPU_ROUTE}/v1/models
```

### 5. Test Inference
```bash
# Simple completion test
curl https://${CPU_ROUTE}/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is Kubernetes?",
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

### 6. Access Web UI
```bash
# Get route URL
oc get route llama-cpp-route -o jsonpath='{.spec.host}'

# Open in browser
# https://<route-url>
```

### 7. Port-Forward for Local Testing
```bash
# Forward CPU deployment
oc port-forward deployment/llama-cpp-server 8080:8080

# Forward GPU deployment
oc port-forward deployment/llama-cpp-server-gpu 8081:8080

# Access locally
# http://localhost:8080 (CPU)
# http://localhost:8081 (GPU)
```

## Performance Comparison

### Measuring Inference Speed
```bash
# Test CPU performance
time curl -X POST https://${CPU_ROUTE}/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain quantum computing in simple terms.",
    "max_tokens": 200
  }'

# Test GPU performance
time curl -X POST https://${GPU_ROUTE}/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain quantum computing in simple terms.",
    "max_tokens": 200
  }'
```

### Expected Performance (Mistral 7B Q4_K_M)
- **CPU**: 5-15 tokens/second (varies by CPU)
- **GPU (A100)**: 50-100+ tokens/second
- **GPU speedup**: 5-10x faster than CPU

### Monitoring GPU Usage
```bash
# Check GPU utilization
oc exec -it deployment/llama-cpp-server-gpu -- nvidia-smi

# Watch GPU usage in real-time
oc exec -it deployment/llama-cpp-server-gpu -- watch -n 1 nvidia-smi
```

## Troubleshooting

### Pod Won't Start
```bash
# Check pod events
oc describe pod <pod-name>

# Common issues:
# - ImagePullBackOff: Wrong image name or no access
# - CrashLoopBackOff: Application error, check logs
# - Pending: Insufficient resources or PVC issues
```

### Model Download Fails
```bash
# Check init container logs
oc logs <pod-name> -c model-downloader

# Common issues:
# - Network timeout: Increase timeout or use different mirror
# - Insufficient disk space: Increase PVC size
# - Wrong URL: Verify MODEL_URL in ConfigMap
```

### Service Not Routing Correctly
```bash
# Check service selectors
oc get svc <service-name> -o yaml | grep -A 5 selector

# Check pod labels
oc get pods --show-labels

# Verify endpoints
oc get endpoints <service-name>

# Common issue: Missing or incorrect accelerator label
```

### GPU Not Being Used
```bash
# Check GPU allocation
oc describe node <gpu-node-name> | grep -A 10 "Allocated resources"

# Check pod GPU request
oc get pod <pod-name> -o yaml | grep -A 5 resources

# Verify CUDA availability in pod
oc exec -it <pod-name> -- nvidia-smi

# Check n-gpu-layers argument
oc logs <pod-name> | grep "n-gpu-layers"
```

### Route Timeout
```bash
# Check route annotations
oc get route <route-name> -o yaml | grep annotations -A 5

# Add timeout annotation if missing
oc annotate route <route-name> haproxy.router.openshift.io/timeout=3h

# Check router logs
oc logs -n openshift-ingress deployment/router-default
```

### Out of Memory
```bash
# Check memory usage
oc adm top pods -n <your-namespace>

# Check pod events for OOMKilled
oc get events --field-selector involvedObject.name=<pod-name>

# Solution: Increase memory limits in deployment
```

## Advanced Configuration

### Using Different Models
To use a different model, update the ConfigMap:

```yaml
data:
  MODEL_URL: "https://huggingface.co/<user>/<model>/resolve/main/<file>.gguf"
  MODEL_NAME: "<file>.gguf"
  CONTEXT_SIZE: "4096"  # Adjust based on model
  GPU_LAYERS: "35"      # Adjust based on model size
```

### Scaling for High Availability
```yaml
spec:
  replicas: 3  # Multiple replicas for load balancing
```

Note: Each replica will download the model unless you pre-populate the PVC.

### Using Pre-downloaded Models
1. Create PVC
2. Create a Job to download model to PVC
3. Remove init container from deployment
4. Deploy application

### Custom Server Arguments
Add to deployment args:
```yaml
args:
- "--threads"
- "8"              # CPU threads
- "--batch-size"
- "512"            # Batch size
- "--ctx-size"
- "4096"           # Context window
- "--rope-freq-base"
- "10000"          # RoPE frequency base
```

## Security Considerations

1. **Network Policies**: Restrict pod-to-pod communication
2. **RBAC**: Limit service account permissions
3. **Route Security**: Use TLS termination (edge)
4. **Resource Quotas**: Prevent resource exhaustion
5. **Pod Security**: Use security context constraints

## Cost Optimization

1. **Use CPU for development/testing**: GPU for production
2. **Scale down when not in use**: `oc scale deployment <name> --replicas=0`
3. **Use smaller quantization**: Q3_K_M vs Q4_K_M for lower memory
4. **Share models**: Use RWX PVC for multiple deployments
5. **Monitor usage**: Remove unused deployments

## Conclusion

This guide provides a complete, production-ready approach to deploying LLMs on OpenShift. Key takeaways:

1. ✅ Use RWX storage from the start
2. ✅ Use specific image tags (`:server`, `:server-cuda`)
3. ✅ Add unique labels for proper service routing
4. ✅ Set appropriate resource limits
5. ✅ Configure route timeouts for long requests
6. ✅ Test thoroughly before production use

For questions or issues, refer to:
- llama.cpp documentation: https://github.com/ggerganov/llama.cpp
- OpenShift documentation: https://docs.openshift.com
- Model repository: https://huggingface.co/TheBloke

## Repository Structure

```
.
├── k8s-manifests/
│   ├── 01-namespace.yaml
│   ├── 02-pvc-rwx.yaml
│   ├── 03-configmap.yaml
│   ├── 04-deployment-cpu-only.yaml
│   ├── 05-service.yaml
│   ├── 06-route.yaml
│   ├── 07-deployment-gpu.yaml
│   ├── 08-service-gpu.yaml
│   └── 09-route-gpu.yaml
├── deploy.sh                    # Automated deployment script
├── test-api.sh                  # API testing script
└── COMPLETE-DEPLOYMENT-GUIDE.md # This file
```

## Quick Start Commands

```bash
# Clone repository
git clone <your-repo-url>
cd openshift-ai

# Customize namespace and model in manifests
# Edit k8s-manifests/01-namespace.yaml
# Edit k8s-manifests/03-configmap.yaml

# Deploy
oc apply -f k8s-manifests/

# Wait for pods to be ready
oc wait --for=condition=ready pod -l app=llama-cpp --timeout=600s

# Get routes
oc get routes

# Test
./test-api.sh
```

---

**Version**: 1.0  
**Last Updated**: 2026-01-07  
**Tested On**: OpenShift 4.14, OpenShift AI 2.25.1