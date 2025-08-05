#!/bin/bash
set -e

# 🎨 Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}\n🚀 INICIANDO CLÚSTER ATALES (Minikube + SealedSecrets + ArgoCD)${NC}"

# 1. Iniciar Minikube
echo -e "${BLUE}\n🔍 Verificando Minikube...${NC}"
if ! minikube status > /dev/null 2>&1; then
  echo -e "${YELLOW}🟡 Iniciando Minikube...${NC}"
  minikube start --cpus=3 --memory=4500mb --driver=docker \
    --addons=ingress,metrics-server,dashboard
else
  echo -e "${GREEN}✅ Minikube ya está corriendo${NC}"
fi

# 2. Configurar /etc/hosts
MINIKUBE_IP=$(minikube ip)
DOMAIN="atales.local"
HOST_ENTRY="$MINIKUBE_IP $DOMAIN"

if ! grep -q "$DOMAIN" /etc/hosts; then
  echo -e "${YELLOW}🔧 Agregando $DOMAIN a /etc/hosts...${NC}"
  echo "$HOST_ENTRY" | sudo tee -a /etc/hosts > /dev/null
else
  echo -e "${GREEN}✅ /etc/hosts ya contiene $DOMAIN${NC}"
fi

# 3. Instalar Sealed Secrets Controller
echo -e "${BLUE}\n🔐 Instalando Sealed Secrets Controller...${NC}"

if ! kubectl get deployment sealed-secrets-controller -n kube-system > /dev/null 2>&1; then
  kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml
else
  echo -e "${GREEN}✅ Sealed Secrets ya está instalado${NC}"
fi

echo -e "${BLUE}⏳ Esperando que Sealed Secrets esté listo...${NC}"
kubectl wait --for=condition=Ready pod -l name=sealed-secrets-controller -n kube-system --timeout=180s

# 4. Aplicar Sealed Secret (archivo sealed secret, que debe estar en la misma carpeta)
SEALED_SECRET_FILE="secret.yaml"

if [ -f "$SEALED_SECRET_FILE" ]; then
  echo -e "${BLUE}\n🔐 Aplicando Sealed Secret desde $SEALED_SECRET_FILE ...${NC}"
  kubectl apply -f "$SEALED_SECRET_FILE"
  echo -e "${GREEN}✅ Sealed Secret aplicada${NC}"
else
  echo -e "${RED}❌ No se encontró el archivo $SEALED_SECRET_FILE. Por favor, colócalo en la misma carpeta que este script.${NC}"
  exit 1
fi

# 5. Instalar kubeseal CLI si no está instalado
echo -e "${BLUE}\n🛠️ Verificando instalación de kubeseal CLI...${NC}"
if ! command -v kubeseal &> /dev/null; then
  echo -e "${YELLOW}🟡 Instalando kubeseal CLI...${NC}"
  VERSION="0.24.0"
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="arm" ;;
  esac

  wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${VERSION}/kubeseal-${VERSION}-${OS}-${ARCH}.tar.gz"
  tar -xvzf "kubeseal-${VERSION}-${OS}-${ARCH}.tar.gz"
  sudo install -m 755 kubeseal /usr/local/bin/kubeseal
  rm -f "kubeseal-${VERSION}-${OS}-${ARCH}.tar.gz" kubeseal
  echo -e "${GREEN}✅ kubeseal instalado correctamente${NC}"
else
  echo -e "${GREEN}✅ kubeseal ya está instalado${NC}"
fi

# 6. Instalar Argo CD
echo -e "${BLUE}\n🛠️ Verificando instalación de Argo CD...${NC}"
if ! kubectl get ns argocd > /dev/null 2>&1; then
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
else
  echo -e "${GREEN}✅ Argo CD ya está instalado${NC}"
fi

echo -e "${BLUE}⏳ Esperando que ArgoCD esté listo...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd > /dev/null 2>&1

# 7. Aplicar aplicaciones Argo CD (carpeta argo-apps)
echo -e "${BLUE}\n🚀 Aplicando aplicaciones Argo CD...${NC}"
APP_DIR="argo-apps"
for file in "$APP_DIR"/*.yaml; do
  if [ -f "$file" ]; then
    echo -e "${YELLOW}📦 Aplicando ${file}...${NC}"
    kubectl apply -f "$file" -n argocd
  fi
done

# 8. Habilitar port-forward Argo CD
echo -e "${YELLOW}\n🚪 Habilitando acceso local a Argo CD en https://localhost:8080 ...${NC}"
pkill -f "kubectl port-forward.*argocd-server" 2>/dev/null || true
sleep 2
kubectl port-forward svc/argocd-server -n argocd 8080:443 > /dev/null 2>&1 &

# 9. Mostrar contraseña Argo CD
echo -e "${GREEN}\n🔑 Contraseña inicial ArgoCD (usuario admin):${NC}"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo -e "\n"

# 10. Mensaje final
echo -e "${GREEN}✅ CLÚSTER LISTO\n"
echo -e "${YELLOW}🔗 ArgoCD: https://localhost:8080"
echo -e "${YELLOW}👤 Usuario: admin"
echo -e "${YELLOW}🔑 Contraseña: (mostrada arriba)"

