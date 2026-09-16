NAME        = inception
COMPOSE     = docker compose -f srcs/docker-compose.yml --env-file srcs/.env
DATA_PATH   = /home/fgalvez-/data

all: up

setup:
	@mkdir -p $(DATA_PATH)/wordpress
	@mkdir -p $(DATA_PATH)/mariadb

build: setup
	$(COMPOSE) build

up: setup
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

clean: down
	@docker system prune -af

fclean: clean
	@docker volume rm $$(docker volume ls -q) 2>/dev/null || true
	@sudo rm -rf $(DATA_PATH)/wordpress/* $(DATA_PATH)/mariadb/*

re: fclean all

.PHONY: all setup build up down stop start logs ps clean fclean re
