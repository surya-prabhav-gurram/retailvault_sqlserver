FROM node:18-alpine AS build
WORKDIR /app
COPY frontend/package*.json ./
RUN npm install --legacy-peer-deps && \
    npm install --legacy-peer-deps ajv@^8 ajv-keywords@^5
COPY frontend/ .
ARG REACT_APP_API_BASE_URL
ENV REACT_APP_API_BASE_URL=$REACT_APP_API_BASE_URL
RUN npm run build

FROM nginx:alpine
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
