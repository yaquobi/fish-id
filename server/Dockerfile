# يُبنى من جذر المستودع: docker compose -f server/docker-compose.yml up -d --build
FROM dart:3.13 AS build
WORKDIR /src
COPY server/pubspec.* ./
RUN dart pub get
COPY server/ ./
RUN mkdir -p /out && dart compile exe bin/server.dart -o /out/server && dart compile exe bin/eval.dart -o /out/fishid-eval

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
# أداة قياس الدقة (server/eval.sh)، تستخدم نفس النموذج والتعليمات.
COPY --from=build /out/fishid-eval /app/fishid-eval
COPY server/eval/species.json /app/eval/species.json
# نفس بيانات الموسوعة اللي داخل التطبيق، فالقائمتان دايمًا متطابقتان.
COPY assets/data/ksafish.json /app/data/ksafish.json
WORKDIR /app
EXPOSE 8080
CMD ["/app/server"]
