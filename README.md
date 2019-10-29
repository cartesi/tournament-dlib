# Tournament Dlib

## Getting Started

### Requirements

- docker
- docker-compose
- jinja2

### Running

To run execute:
```
jinja2 -D num_players=3 docker-compose-template.yml | docker-compose -f - up -d --build
```

To shutdown:
```
jinja2 -D num_players=3 docker-compose-template.yml | docker-compose -f - down -v
```

You can follow the output of a docker instance with:
```
docker logs -f [name of the instance]
```
