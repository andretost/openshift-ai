#!/bin/bash

# Deployment script for Mistral 7B with llama.cpp on OpenShift
# This script deploys all Kubernetes resources in the correct order

set -e

NAMESPACE="andre-llama-cpp"
MANIFESTS_DIR="k8s-manifests"

echo "=========================================="
echo "Mistral 7B llama.cpp Deployment Script"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if oc command is available
if ! command -v oc &> /dev/null; then
    print_error "oc command not found. Please install OpenShift CLI."
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    print_error "Not logged in to OpenShift. Please run 'oc login' first."
    exit 1
fi

print_status "Logged in as: $(oc whoami)"
print_status "Current cluster: $(oc whoami --show-server)"
echo ""

# Step 1: Create namespace
echo "Step 1: Creating namespace..."
if oc get namespace ${NAMESPACE} &> /dev/null; then
    print_warning "Namespace ${NAMESPACE} already exists. Skipping creation."
else
    oc apply -f ${MANIFESTS_DIR}/01-namespace.yaml
    print_status "Namespace created successfully"
fi
echo ""

# Step 2: Switch to the namespace
echo "Step 2: Switching to namespace ${NAMESPACE}..."
oc project ${NAMESPACE}
print_status "Now using namespace: ${NAMESPACE}"
echo ""

# Step 3: Create PVC
echo "Step 3: Creating PersistentVolumeClaim..."
oc apply -f ${MANIFESTS_DIR}/02-pvc.yaml
print_status "PVC created successfully"
echo ""

# Wait for PVC to be bound
echo "Waiting for PVC to be bound..."
timeout=60
counter=0
while [ $counter -lt $timeout ]; do
    status=$(oc get pvc model-storage -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$status" == "Bound" ]; then
        print_status "PVC is bound"
        break
    fi
    echo -n "."
    sleep 2
    counter=$((counter + 2))
done
echo ""

if [ "$status" != "Bound" ]; then
    print_warning "PVC is not bound yet. Status: $status"
    print_warning "Continuing anyway. Check PVC status with: oc get pvc -n ${NAMESPACE}"
fi
echo ""

# Step 4: Create ConfigMap
echo "Step 4: Creating ConfigMap..."
oc apply -f ${MANIFESTS_DIR}/03-configmap.yaml
print_status "ConfigMap created successfully"
echo ""

# Step 5: Create Deployment
echo "Step 5: Creating Deployment..."
print_warning "This will start downloading the Mistral 7B model (~4GB)"
print_warning "The init container will download the model to the PVC"
oc apply -f ${MANIFESTS_DIR}/04-deployment.yaml
print_status "Deployment created successfully"
echo ""

# Step 6: Create Service
echo "Step 6: Creating Service..."
oc apply -f ${MANIFESTS_DIR}/05-service.yaml
print_status "Service created successfully"
echo ""

# Step 7: Create Route
echo "Step 7: Creating Route..."
oc apply -f ${MANIFESTS_DIR}/06-route.yaml
print_status "Route created successfully"
echo ""

# Get route URL
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo ""

ROUTE_URL=$(oc get route llama-cpp-route -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$ROUTE_URL" ]; then
    print_status "Route URL: https://${ROUTE_URL}"
else
    print_warning "Could not retrieve route URL"
fi
echo ""

print_status "All resources deployed successfully!"
echo ""
echo "Next steps:"
echo "1. Monitor the deployment:"
echo "   oc get pods -n ${NAMESPACE} -w"
echo ""
echo "2. Check init container logs (model download):"
echo "   oc logs -n ${NAMESPACE} -l app=llama-cpp -c model-downloader -f"
echo ""
echo "3. Check main container logs:"
echo "   oc logs -n ${NAMESPACE} -l app=llama-cpp -c llama-cpp-server -f"
echo ""
echo "4. Once the pod is ready, test the API:"
echo "   curl https://${ROUTE_URL}/health"
echo ""
echo "5. For detailed usage instructions, see: USAGE.md"
echo ""
echo "=========================================="