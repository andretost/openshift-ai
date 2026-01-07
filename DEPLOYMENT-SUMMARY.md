# Mistral 7B Deployment Summary

## 🎉 Deployment Complete!

You now have **two separate deployments** of Mistral 7B running on OpenShift, allowing you to compare CPU vs GPU performance.

## 📊 Deployment Overview

| Deployment | Accelerator | Image | GPU Layers | Resources |
|------------|-------------|-------|------------|-----------|
| **CPU** | None | `ghcr.io/ggml-org/llama.cpp:server` | 0 | 4 CPU, 8Gi RAM |
| **GPU** | NVIDIA A100 MIG | `ghcr.io/ggml-org/llama.cpp:server-cuda` | 35 (all) | 4 CPU, 16Gi RAM, 1 GPU |

## 🌐 Access URLs

### CPU Deployment (Web UI & API)
**URL**: https://llama-cpp-route-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au

- **Web UI**: Open in browser for interactive chat
- **API Endpoint**: Use for programmatic access
- **Performance**: ~18-20 tokens/second

### GPU Deployment (Web UI & API)
**URL**: https://llama-cpp-route-gpu-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au

- **Web UI**: Open in browser for interactive chat
- **API Endpoint**: Use for programmatic access
- **Performance**: Expected 80-150+ tokens/second (GPU accelerated)
- **GPU**: NVIDIA A100-PCIE-40GB MIG 3g.20gb with 19.8GB VRAM

## 🚀 Quick Start

### Access Web UI
Simply open either URL in your browser:
- **CPU**: https://llama-cpp-route-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au
- **GPU**: https://llama-cpp-route-gpu-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au

### Test API Endpoints

#### CPU Endpoint
```bash
curl -k -X POST https://llama-cpp-route-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au/completion \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Explain AI in simple terms:","n_predict":100}'
```

#### GPU Endpoint
```bash
curl -k -X POST https://llama-cpp-route-gpu-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au/completion \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Explain AI in simple terms:","n_predict":100}'
```

### Compare Performance

Run the same prompt on both endpoints and compare the `predicted_per_second` value in the response to see the GPU speedup!

## 📦 Deployed Resources

### Namespace
- **Name**: `andre-llama-cpp`
- **Purpose**: Isolated environment for both deployments

### Storage
- **PVC**: `model-storage-rwx` (30GB, ReadWriteMany, CephFS)
- **Model**: Mistral 7B Instruct v0.2 (Q4_K_M quantization, 4.1GB)
- **Shared**: Both deployments use the same model file

### Deployments
1. **llama-cpp-server** (CPU)
   - Replicas: 1
   - Service: `llama-cpp-service`
   - Route: `llama-cpp-route`

2. **llama-cpp-server-gpu** (GPU)
   - Replicas: 1
   - Service: `llama-cpp-service-gpu`
   - Route: `llama-cpp-route-gpu`
   - GPU: 1x NVIDIA A100 MIG (3g.20gb profile)

## 🔍 Monitoring

### Check Pod Status
```bash
oc get pods -n andre-llama-cpp
```

### View Logs
```bash
# CPU deployment
oc logs -n andre-llama-cpp -l app=llama-cpp,accelerator!=gpu -f

# GPU deployment
oc logs -n andre-llama-cpp -l app=llama-cpp,accelerator=gpu -f
```

### Check GPU Usage
```bash
# Get GPU pod name
GPU_POD=$(oc get pods -n andre-llama-cpp -l accelerator=gpu -o jsonpath='{.items[0].metadata.name}')

# View GPU info from logs
oc logs -n andre-llama-cpp $GPU_POD | grep -i "cuda\|gpu"
```

## 📈 Performance Comparison

### Expected Performance

| Metric | CPU | GPU | Speedup |
|--------|-----|-----|---------|
| Tokens/sec | ~18-20 | ~80-150+ | **4-8x faster** |
| First token latency | ~1-2s | ~0.2-0.5s | **2-4x faster** |
| Concurrent requests | Limited | Better | GPU handles parallel better |

### Benchmark Commands

```bash
# CPU benchmark
time curl -k -s -X POST https://llama-cpp-route-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au/completion \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Write a story about AI:","n_predict":200}' > /dev/null

# GPU benchmark
time curl -k -s -X POST https://llama-cpp-route-gpu-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au/completion \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Write a story about AI:","n_predict":200}' > /dev/null
```

## 🛠️ Management Commands

### Scale Deployments
```bash
# Scale CPU deployment
oc scale deployment llama-cpp-server -n andre-llama-cpp --replicas=0  # Stop
oc scale deployment llama-cpp-server -n andre-llama-cpp --replicas=1  # Start

# Scale GPU deployment
oc scale deployment llama-cpp-server-gpu -n andre-llama-cpp --replicas=0  # Stop
oc scale deployment llama-cpp-server-gpu -n andre-llama-cpp --replicas=1  # Start
```

### Update Configuration
```bash
# Edit ConfigMap
oc edit configmap llama-cpp-config -n andre-llama-cpp

# Restart deployments to apply changes
oc rollout restart deployment llama-cpp-server -n andre-llama-cpp
oc rollout restart deployment llama-cpp-server-gpu -n andre-llama-cpp
```

### View Resource Usage
```bash
# CPU and memory usage
oc adm top pods -n andre-llama-cpp

# Detailed resource info
oc describe pod -n andre-llama-cpp -l app=llama-cpp
```

## 🔧 Troubleshooting

### Pod Not Starting
```bash
# Check events
oc get events -n andre-llama-cpp --sort-by='.lastTimestamp'

# Describe pod
oc describe pod -n andre-llama-cpp -l app=llama-cpp
```

### API Not Responding
```bash
# Check if pods are ready
oc get pods -n andre-llama-cpp

# Test health endpoint
curl -k https://llama-cpp-route-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au/health
curl -k https://llama-cpp-route-gpu-andre-llama-cpp.apps.fusion.isys.hpc.dc.uq.edu.au/health
```

### GPU Not Being Used
```bash
# Check GPU allocation
oc describe node | grep -A 5 "nvidia.com/gpu"

# Verify GPU in pod logs
oc logs -n andre-llama-cpp -l accelerator=gpu | grep "CUDA"
```

## 📚 Additional Resources

- **Detailed Usage Guide**: See `USAGE.md` for API examples and Python code
- **Architecture Documentation**: See `deployment-plan.md` for technical details
- **Deployment Scripts**: Use `deploy.sh` for automated deployment
- **Testing**: Run `test-api.sh` for comprehensive API testing

## 🎯 Next Steps

1. **Compare Performance**: Try the same prompts on both URLs and compare response times
2. **Explore the Web UI**: Open both URLs in separate browser tabs
3. **Test Different Prompts**: Try various use cases (coding, writing, analysis)
4. **Monitor Resources**: Watch CPU/GPU usage during inference
5. **Tune Parameters**: Adjust temperature, top-k, top-p in the Web UI or API calls

## 📊 Current Status

```bash
# Quick status check
oc get pods,svc,route -n andre-llama-cpp
```

Both deployments are **running and ready** for use! 🚀

---

**Model**: Mistral 7B Instruct v0.2 (Q4_K_M)  
**Namespace**: andre-llama-cpp  
**Cluster**: fusion.isys.hpc.dc.uq.edu.au  
**Deployment Date**: 2026-01-07