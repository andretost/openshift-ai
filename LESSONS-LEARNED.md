# Lessons Learned: LLM Deployment on OpenShift

Quick reference of all pitfalls encountered and solutions found during this deployment.

## Critical Decisions

### ✅ DO

1. **Use ReadWriteMany (RWX) PVC from the start**
   - Allows multiple pods to share the same model file
   - Essential for CPU + GPU deployments
   - Storage classes: CephFS, NFS

2. **Use specific image tags**
   - CPU: `ghcr.io/ggml-org/llama.cpp:server`
   - GPU: `ghcr.io/ggml-org/llama.cpp:server-cuda`
   - Never use `:latest` or `:light`

3. **Add unique labels to each deployment**
   ```yaml
   labels:
     app: llama-cpp
     component: server
     accelerator: cpu  # or gpu
   ```

4. **Match service selectors to deployment labels**
   ```yaml
   selector:
     app: llama-cpp
     component: server
     accelerator: cpu  # Must match deployment
   ```

5. **Set route timeout for long requests**
   ```yaml
   annotations:
     haproxy.router.openshift.io/timeout: 3h
   ```

6. **Configure appropriate GPU layers**
   - Mistral 7B: 35 layers
   - Adjust based on model size and GPU memory

### ❌ DON'T

1. **Don't use ReadWriteOnce (RWO) if you need multiple pods**
   - Can't mount to multiple pods simultaneously
   - Requires data migration to switch to RWX

2. **Don't use generic image tags**
   - `:latest` may not include server binary
   - `:light` is missing required components

3. **Don't forget the accelerator label**
   - Services will route to wrong pods
   - Causes intermittent failures

4. **Don't set GPU layers to 0 for GPU deployment**
   - GPU won't be utilized
   - No performance benefit

5. **Don't use default route timeout**
   - Will timeout on long inference requests
   - Default is usually 30s

## Pitfalls Encountered

### 1. PVC Access Mode Issue
**Problem**: Started with ReadWriteOnce (RWO) PVC, couldn't add GPU deployment.

**Symptom**: Second pod fails with "Multi-Attach error for volume"

**Solution**: 
- Create new RWX PVC
- Copy model data using Job
- Update deployments to use new PVC

**Prevention**: Use RWX storage class from the beginning.

### 2. Wrong Image Tag
**Problem**: Used `:light` tag which didn't include server binary.

**Symptom**: Pod crashes with "server: command not found"

**Solution**: Switch to `:server` (CPU) or `:server-cuda` (GPU) tags.

**Prevention**: Always use specific, tested image tags.

### 3. Service Selector Overlap
**Problem**: CPU service selector matched both CPU and GPU pods.

**Symptom**: 
- GPU route shows "Server unavailable"
- Requests randomly succeed or fail
- Wrong pod responding to requests

**Solution**: 
- Add `accelerator: cpu` label to CPU deployment
- Add `accelerator: cpu` to CPU service selector
- Ensure GPU deployment has `accelerator: gpu`

**Prevention**: Always use unique labels for different deployment types.

### 4. GPU Not Utilized
**Problem**: GPU deployment running but not using GPU.

**Symptom**: Performance same as CPU deployment.

**Solution**: Set `--n-gpu-layers` to appropriate value (35 for Mistral 7B).

**Prevention**: Always configure GPU layers in deployment args.

### 5. Route Timeout
**Problem**: Long inference requests timing out.

**Symptom**: 504 Gateway Timeout after 30 seconds.

**Solution**: Add route annotation `haproxy.router.openshift.io/timeout: 3h`.

**Prevention**: Set timeout annotation when creating routes.

## Debugging Commands

### Check Pod Status
```bash
oc get pods -n <your-namespace>
oc describe pod <pod-name>
oc logs <pod-name>
oc logs <pod-name> -c <container-name>  # For init containers
```

### Verify Service Routing
```bash
oc get svc -o wide
oc get endpoints
oc describe svc <service-name>
```

### Test from Within Cluster
```bash
oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n <your-namespace> \
  -- curl -sS http://<service-name>:8080/v1/models
```

### Check GPU Usage
```bash
oc exec -it <pod-name> -- nvidia-smi
oc exec -it <pod-name> -- watch -n 1 nvidia-smi
```

### Port Forward for Local Testing
```bash
oc port-forward deployment/<deployment-name> 8080:8080
```

### Check Labels
```bash
oc get pods --show-labels
oc get svc <service-name> -o yaml | grep -A 5 selector
```

## Performance Expectations

### Mistral 7B Q4_K_M
- **CPU**: 5-15 tokens/second
- **GPU (A100)**: 50-100+ tokens/second
- **Speedup**: 5-10x

### Resource Requirements
- **7B model**: 8-16Gi memory
- **13B model**: 16-32Gi memory
- **70B model**: 64Gi+ memory

## Testing Checklist

- [ ] Pods are running (1/1 Ready)
- [ ] Services have correct endpoints
- [ ] Routes are accessible
- [ ] API returns model information
- [ ] Inference requests complete successfully
- [ ] GPU is being utilized (if GPU deployment)
- [ ] Web UI is accessible
- [ ] Performance meets expectations

## Quick Fixes

### Pod CrashLoopBackOff
1. Check logs: `oc logs <pod-name>`
2. Check events: `oc describe pod <pod-name>`
3. Common causes: wrong image, missing model, insufficient resources

### Service Not Routing
1. Check endpoints: `oc get endpoints <service-name>`
2. Verify labels: `oc get pods --show-labels`
3. Check selector: `oc get svc <service-name> -o yaml`

### Route Timeout
1. Add timeout annotation: `oc annotate route <route-name> haproxy.router.openshift.io/timeout=3h`
2. Verify: `oc get route <route-name> -o yaml | grep timeout`

### GPU Not Used
1. Check GPU allocation: `oc describe node <node-name>`
2. Verify GPU request: `oc get pod <pod-name> -o yaml | grep nvidia.com/gpu`
3. Check n-gpu-layers: `oc logs <pod-name> | grep "n-gpu-layers"`

## Best Practices

1. **Start with CPU deployment** - Verify everything works before adding GPU
2. **Use RWX storage** - Even if you only have one deployment initially
3. **Monitor resource usage** - Use `oc adm top pods` to check actual usage
4. **Test incrementally** - Deploy one component at a time
5. **Document your changes** - Keep track of customizations
6. **Use version control** - Commit manifests to git
7. **Test from within cluster first** - Before testing external routes
8. **Set appropriate resource limits** - Based on model size
9. **Use health checks** - Liveness and readiness probes
10. **Plan for scaling** - Design for multiple replicas if needed

## Migration Path

If you started with RWO and need to migrate to RWX:

1. Create new RWX PVC
2. Create Job to copy data:
   ```yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: copy-model
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
3. Update deployments to use new PVC
4. Delete old PVC

## Summary

The key to successful deployment:
1. ✅ Use RWX storage
2. ✅ Use correct image tags
3. ✅ Add unique labels
4. ✅ Match service selectors
5. ✅ Configure timeouts
6. ✅ Set GPU layers
7. ✅ Test thoroughly

Follow these guidelines and you'll avoid the pitfalls we encountered!

---

**For detailed step-by-step instructions, see [COMPLETE-DEPLOYMENT-GUIDE.md](COMPLETE-DEPLOYMENT-GUIDE.md)**