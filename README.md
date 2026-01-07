# LLM Deployment with llama.cpp on OpenShift

Deploy and run large language models using llama.cpp on OpenShift with optional GPU acceleration.

## 📚 Complete Documentation

**→ [COMPLETE DEPLOYMENT GUIDE](COMPLETE-DEPLOYMENT-GUIDE.md)** - Comprehensive guide with step-by-step instructions, all lessons learned, common pitfalls, and solutions. **Start here for your first deployment!**

### Additional Documentation
- [Usage Guide](USAGE.md) - How to interact with the deployed model
- [Deployment Summary](DEPLOYMENT-SUMMARY.md) - Architecture and components overview
- [Service Routing Fix](SERVICE-ROUTING-FIX.md) - Technical details on service selector fix

## 🚀 Quick Start

### Prerequisites
- OpenShift cluster access with `oc` CLI configured
- Storage class supporting ReadWriteMany (RWX) access mode
- (Optional) GPU resources for acceleration

### Deploy in 3 Steps

1. **Customize the configuration**
   ```bash
   # Edit namespace name
   vi k8s-manifests/01-namespace.yaml
   
   # Edit model URL and settings
   vi k8s-manifests/03-configmap.yaml
   
   # Update storage class name to your cluster's RWX storage class
   vi k8s-manifests/02-pvc-rwx.yaml
   ```

2. **Deploy**
   ```bash
   # Deploy all components
   oc apply -f k8s-manifests/
   
   # Or use the automated script
   ./deploy.sh
   ```

3. **Access**
   ```bash
   # Get the route URL
   oc get route llama-cpp-route -o jsonpath='{.spec.host}'
   
   # Open in browser or test with curl
   curl https://<route-url>/v1/models
   ```

## 🎯 What This Deploys

- **CPU Deployment**: Baseline LLM inference using CPU
- **GPU Deployment**: Accelerated inference using NVIDIA GPUs (optional)
- **Persistent Storage**: 30GB RWX PVC for model storage
- **Web UI**: Interactive chat interface at `https://<route-url>`
- **API Endpoints**: OpenAI-compatible REST API
- **Routes**: External HTTPS access to both deployments

## 📊 Features

✅ **Dual Deployment**: Compare CPU vs GPU performance  
✅ **Shared Storage**: Single model file used by both deployments  
✅ **Auto-Download**: Models downloaded automatically on first run  
✅ **Web Interface**: Built-in chat UI  
✅ **API Compatible**: OpenAI-compatible endpoints  
✅ **Production Ready**: Health checks, resource limits, proper routing  

## 🏗️ Repository Structure

```
.
├── k8s-manifests/
│   ├── 01-namespace.yaml              # Namespace definition
│   ├── 02-pvc-rwx.yaml                # ReadWriteMany PVC for model storage
│   ├── 03-configmap.yaml              # Model URL and configuration
│   ├── 04-deployment-cpu-only.yaml    # CPU-based deployment
│   ├── 05-service.yaml                # CPU service
│   ├── 06-route.yaml                  # CPU route
│   ├── 07-deployment-gpu.yaml         # GPU-accelerated deployment
│   ├── 08-service-gpu.yaml            # GPU service
│   └── 09-route-gpu.yaml              # GPU route
├── deploy.sh                          # Automated deployment script
├── test-api.sh                        # API testing script
├── COMPLETE-DEPLOYMENT-GUIDE.md       # 📖 Full guide with lessons learned
├── USAGE.md                           # Usage instructions
├── DEPLOYMENT-SUMMARY.md              # Architecture overview
└── SERVICE-ROUTING-FIX.md             # Technical fix documentation
```

## 🔧 Quick Configuration

### Model Selection
Default: **Mistral 7B Instruct v0.2** (Q4_K_M quantization, ~4GB)

To use a different model, edit `k8s-manifests/03-configmap.yaml`:
```yaml
data:
  MODEL_URL: "https://huggingface.co/<user>/<model>/resolve/main/<file>.gguf"
  MODEL_NAME: "<file>.gguf"
```

Popular alternatives:
- **TinyLlama 1.1B**: ~600MB, fast inference
- **Llama 2 13B**: ~7GB, better quality
- **Mixtral 8x7B**: ~26GB, highest quality

### Storage Class
Update `k8s-manifests/02-pvc-rwx.yaml` with your cluster's RWX storage class:
```yaml
spec:
  storageClassName: your-rwx-storage-class  # e.g., ocs-storagecluster-cephfs, nfs-client
```

**Important**: Must support ReadWriteMany (RWX) access mode!

### GPU Configuration
Adjust GPU layers in `k8s-manifests/03-configmap.yaml`:
```yaml
data:
  GPU_LAYERS: "35"  # Number of layers to offload to GPU (0 = CPU only)
```

## 🧪 Testing

### Test API Endpoints
```bash
# Run automated tests
./test-api.sh

# Or test manually
CPU_ROUTE=$(oc get route llama-cpp-route -o jsonpath='{.spec.host}')
curl https://${CPU_ROUTE}/v1/models
```

### Test Inference
```bash
curl https://${CPU_ROUTE}/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is Kubernetes?",
    "max_tokens": 100
  }'
```

### Access Web UI
```bash
# Get URL
oc get route llama-cpp-route -o jsonpath='{.spec.host}'

# Open in browser: https://<route-url>
```

## 📈 Performance

Expected performance with Mistral 7B Q4_K_M:
- **CPU**: 5-15 tokens/second
- **GPU (A100)**: 50-100+ tokens/second
- **Speedup**: 5-10x with GPU acceleration

## ⚠️ Important Notes

1. **Use RWX Storage**: Required for multiple deployments sharing the same model
2. **Correct Image Tags**: Use `:server` for CPU, `:server-cuda` for GPU
3. **Unique Labels**: Each deployment needs `accelerator: cpu/gpu` label for proper routing
4. **Resource Limits**: Set appropriate memory limits based on model size
5. **Route Timeouts**: Configure 3h timeout for long inference requests

## 🐛 Common Issues & Solutions

### Pod won't start?
```bash
oc describe pod <pod-name>
oc logs <pod-name>
```

### Service not routing correctly?
```bash
oc get endpoints
oc get svc -o wide
# Check for proper accelerator labels
```

### GPU not being used?
```bash
oc exec -it deployment/llama-cpp-server-gpu -- nvidia-smi
```

### Route timing out?
- Check route annotations for timeout settings
- Verify network connectivity to cluster
- Try port-forward: `oc port-forward deployment/llama-cpp-server 8080:8080`

**See [Complete Deployment Guide](COMPLETE-DEPLOYMENT-GUIDE.md) for detailed troubleshooting.**

## 🎓 Learning Resources

- [llama.cpp GitHub](https://github.com/ggerganov/llama.cpp) - Inference engine
- [OpenShift Documentation](https://docs.openshift.com) - Platform docs
- [Hugging Face Models](https://huggingface.co/TheBloke) - Pre-quantized models
- [GGUF Format Guide](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md) - Model format

## 🤝 Contributing

This repository documents a complete deployment journey including all pitfalls encountered and solutions found. Contributions welcome:
- Report issues
- Suggest improvements
- Share deployment experiences
- Add support for other models

## 📝 License

MIT

## 🙏 Acknowledgments

- **llama.cpp team** for the excellent inference engine
- **TheBloke** for quantized model distributions
- **OpenShift AI team** for GPU support

---

**Version**: 1.0  
**Last Updated**: 2026-01-07  
**Tested On**: OpenShift 4.14, OpenShift AI 2.25.1