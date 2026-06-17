# Innovatech Chile — EP3: Orquestación y CI/CD en AWS EKS

## Descripción general

Este proyecto implementa la orquestación y automatización productiva de la aplicación **Innovatech Chile** sobre **AWS EKS (Kubernetes)**. Incluye despliegue de servicios Frontend y dos Backends, autoscaling con HPA, pipeline CI/CD completo con GitHub Actions, y gestión segura de secretos.

---

## Arquitectura

```
Internet
    │
    ▼
[AWS ELB - LoadBalancer]
    │  (puerto 80)
    ▼
[Frontend - React/Nginx]   ← Deployment K8s (innovatech-frontend)
    │
    ├──→ [Backend Ventas]  ← ClusterIP: backend-ventas:8080
    │         │
    └──→ [Backend Despachos] ← ClusterIP: backend-despachos:8081
                │
                ▼
           [MySQL]         ← ClusterIP: mysql:3306
```

**Componentes AWS:**
- **VPC**: `10.0.0.0/16` con 2 subredes públicas en `us-east-1a` y `us-east-1b`
- **EKS Cluster**: `innovatech-cluster` con node group `t3.medium` (2 nodos, hasta 4)
- **ECR**: 3 repositorios (`innovatech-frontend`, `innovatech-backend-ventas`, `innovatech-backend-despachos`)
- **Security Groups**: puertos 80, 8080, 8081, 3306, 30000-32767
- **IAM**: `LabRole` (AWS Academy) para EKS cluster y nodos

**Comunicación Front → Back:**
El frontend se comunica con los backends a través del DNS interno de Kubernetes (`backend-ventas:8080` y `backend-despachos:8081`). Ambos backends son servicios tipo `ClusterIP`, accesibles solo dentro del clúster. El frontend es el único expuesto públicamente via `LoadBalancer`.

---

## Estructura del repositorio

```
├── .github/workflows/
│   └── cd.yml                        # Pipeline CI/CD principal (EKS)
├── back-Ventas_SpringBoot/           # API REST Ventas (Spring Boot)
│   ├── Dockerfile
│   └── Springboot-API-REST/
├── back-Despachos_SpringBoot/        # API REST Despachos (Spring Boot)
│   ├── Dockerfile
│   └── Springboot-API-REST-DESPACHO/
├── front_despacho/                   # Frontend React + Vite + Nginx
│   ├── Dockerfile
│   └── nginx.conf
├── infra/
│   ├── k8s/                          # Manifiestos Kubernetes
│   │   ├── backend-ventas.yml
│   │   ├── backend-despachos.yml
│   │   ├── frontend.yml
│   │   ├── mysql.yml
│   │   ├── hpa.yml                   # Horizontal Pod Autoscaler
│   │   └── secrets.yml               # Estructura de secrets (sin valores reales)
│   └── terraform/
│       └── main.tf                   # Infraestructura AWS (VPC, EKS, ECR, SG)
├── docker-compose.yml                # Entorno local de desarrollo
├── .env.example                      # Variables de entorno (plantilla, sin valores reales)
└── README.md
```

---

## Requisitos previos

- AWS CLI configurado con credenciales de AWS Academy
- Terraform >= 1.5
- kubectl
- Docker Desktop
- Git

---

## Paso a paso: Despliegue

### 1. Clonar el repositorio

```bash
git clone <url-del-repo>
cd EV3_PRUEBA
```

### 2. Provisionar infraestructura con Terraform

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

Esto crea: VPC, subredes, Security Groups, Internet Gateway, clúster EKS, node group y repositorios ECR.

### 3. Configurar kubectl para el clúster EKS

```bash
aws eks update-kubeconfig --region us-east-1 --name innovatech-cluster
kubectl get nodes   # Verificar que los nodos estén Ready
```

### 4. Crear los secrets en Kubernetes

Los valores reales **nunca se suben al repositorio**. Se crean directamente en el clúster:

```bash
kubectl create secret generic mysql-secret \
  --from-literal=MYSQL_ROOT_PASSWORD=<password> \
  --from-literal=MYSQL_DATABASE=innovatech_db \
  --from-literal=MYSQL_USER=appuser \
  --from-literal=MYSQL_PASSWORD=<password> \
  --from-literal=SPRING_DATASOURCE_USERNAME=appuser \
  --from-literal=SPRING_DATASOURCE_PASSWORD=<password>
```

En GitHub Actions, estos valores se guardan como **GitHub Secrets** y se inyectan automáticamente en el pipeline.

### 5. Subir imágenes a ECR (lo hace el pipeline automáticamente)

El pipeline `cd.yml` realiza este proceso al hacer push a la rama `deploy`:

```bash
git push origin deploy
```

Flujo del pipeline:
1. Checkout del código
2. Configurar credenciales AWS desde GitHub Secrets
3. Login en ECR
4. Build de las 3 imágenes (linux/amd64)
5. Push a ECR con tag del SHA del commit
6. Crear/actualizar secrets en K8s
7. Aplicar manifiestos K8s
8. Actualizar imágenes en los deployments
9. Verificar rollout de cada deployment
10. Mostrar estado del clúster y URL pública

### 6. Verificar el despliegue

```bash
# Ver pods en ejecución
kubectl get pods -o wide

# Ver servicios y URL pública del frontend
kubectl get services

# Obtener URL pública del frontend
kubectl get service frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Ver HPA (autoscaling)
kubectl get hpa
```

---

## Pipeline CI/CD

**Archivo:** `.github/workflows/cd.yml`  
**Trigger:** Push a rama `deploy`

**GitHub Secrets requeridos:**

| Secret | Descripción |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | Credencial AWS Academy |
| `AWS_SECRET_ACCESS_KEY` | Credencial AWS Academy |
| `AWS_SESSION_TOKEN` | Token de sesión AWS Academy |
| `MYSQL_ROOT_PASSWORD` | Password root MySQL |
| `MYSQL_DATABASE` | Nombre de la base de datos |
| `MYSQL_USER` | Usuario de la aplicación |
| `MYSQL_PASSWORD` | Password del usuario de la aplicación |

---

## Autoscaling (HPA)

Se configuró **Horizontal Pod Autoscaler** para los 3 servicios con umbral de **50% de CPU**.

**Justificación del 50%:** Permite absorber picos de tráfico antes de que afecten el rendimiento, sin escalar innecesariamente en condiciones normales. Con réplicas entre 1 y 4, el sistema puede multiplicar su capacidad por 4x automáticamente.

**Verificar estado del HPA:**
```bash
kubectl get hpa
kubectl describe hpa hpa-backend-ventas
```

**Simular carga para probar autoscaling:**
```bash
kubectl run -i --tty load-generator --rm --image=busybox \
  --restart=Never -- /bin/sh -c \
  "while sleep 0.01; do wget -q -O- http://backend-ventas:8080/api/v1/ventas; done"

# En otra terminal, observar el escalado:
kubectl get hpa --watch
```

---

## Logs y métricas

**Ver logs de un servicio en tiempo real:**
```bash
# Logs del frontend
kubectl logs -l app=frontend --follow

# Logs del backend ventas
kubectl logs -l app=backend-ventas --follow

# Logs del backend despachos
kubectl logs -l app=backend-despachos --follow
```

**Ver logs en CloudWatch:**
Los logs de los nodos EKS se pueden configurar en CloudWatch Logs habilitando el logging del clúster:
```bash
aws eks update-cluster-config \
  --region us-east-1 \
  --name innovatech-cluster \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

**Métricas del pipeline (GitHub Actions):**
Disponibles en la pestaña Actions del repositorio: tiempo de build, tiempo de push, resultado de cada step.

---

## Desarrollo local

Para ejecutar el proyecto localmente sin necesidad de AWS:

```bash
# Copiar variables de entorno
cp .env.example .env
# Editar .env con tus valores locales

# Levantar todos los servicios
docker compose up --build

# Accesos:
# Frontend:          http://localhost:80
# Backend Ventas:    http://localhost:3000/api/v1/ventas
# Backend Despachos: http://localhost:8080/api/v1/despachos
```

---

## Validación funcional

**Endpoints disponibles:**

| Servicio | Endpoint | Tipo |
|----------|----------|------|
| Frontend | `http://<EXTERNAL-IP>/` | Público (LoadBalancer) |
| Backend Ventas | `http://backend-ventas:8080/api/v1/ventas` | Interno (ClusterIP) |
| Backend Despachos | `http://backend-despachos:8081/api/v1/despachos` | Interno (ClusterIP) |

**Verificar comunicación Front → Back desde dentro del clúster:**
```bash
# Crear pod temporal para probar conectividad interna
kubectl run test-curl --rm -it --image=curlimages/curl --restart=Never -- \
  curl http://backend-ventas:8080/api/v1/ventas

kubectl run test-curl --rm -it --image=curlimages/curl --restart=Never -- \
  curl http://backend-despachos:8081/api/v1/despachos
```

**Verificar recuperación post-redeploy:**
```bash
# Forzar un redeploy (simula lo que hace el pipeline)
kubectl rollout restart deployment/backend-ventas
kubectl rollout status deployment/backend-ventas

# Los pods nuevos arrancan antes de que los viejos se terminen (rolling update)
kubectl get pods --watch
```

---

## Tecnologías utilizadas

- **AWS EKS** — Orquestación de contenedores
- **AWS ECR** — Registro de imágenes Docker
- **Terraform** — Infraestructura como código
- **GitHub Actions** — Pipeline CI/CD
- **Spring Boot** — Backend Java (Ventas y Despachos)
- **React + Vite + Nginx** — Frontend
- **MySQL 8.0** — Base de datos
- **Kubernetes HPA** — Autoscaling automático
