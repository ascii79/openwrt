curl -fSL -o docker-compose.yml \
  https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
docker compose -f docker-compose.yml -f docker-compose.immich.yml -p immich up -d
