# ============================================================
# Stage 1: Build — Compilar la app React con Vite
# ============================================================
FROM node:18-alpine AS build

WORKDIR /app

# Copiar dependencias primero (cache de capas)
COPY package*.json ./
RUN npm install

# Copiar código fuente y compilar
COPY . .
RUN npm run build

# ============================================================
# Stage 2: Production — Nginx para servir archivos estáticos
# ============================================================
FROM nginx:1.25-alpine

# Eliminar configuración por defecto
RUN rm -f /etc/nginx/conf.d/default.conf

# Copiar configuración personalizada
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copiar el build de React
COPY --from=build /app/dist /usr/share/nginx/html

# NOTA: Comentamos la configuración del usuario no-root para que Nginx 
# tenga permisos de usar el puerto 80 (reservado por Linux).
# RUN chown -R nginx:nginx ...
# USER nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]