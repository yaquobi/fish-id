# يُبنى من جذر المستودع: docker compose -f server/docker-compose.yml up -d --build
FROM dart:3.13 AS build
WORKDIR /src
COPY server/pubspec.* ./
RUN dart pub get
COPY server/ ./
RUN dart compile exe bin/server.dart -o /out/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
# نفس بيانات الموسوعة اللي داخل التطبيق، فالقائمتان دايمًا متطابقتان.
COPY assets/data/ksafish.json /app/data/ksafish.json
WORKDIR /app
EXPOSE 8080
CMD ["/app/server"]
