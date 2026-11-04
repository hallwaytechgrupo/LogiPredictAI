FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY flutter_app/ ./

ARG API_BASE_URL=http://localhost:8080
RUN flutter pub get \
    && flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM nginx:1.27-alpine
COPY flutter_app/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
