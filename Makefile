
NAME        = inception
COMPOSE     = docker compose -f srcs/docker-compose.yml --env-file srcs/.env
DATA_PATH   = /home/fgalvez-/data

all: up

secrets:
	@mkdir -p secrets
	@test -f secrets/db_root_password.txt || openssl rand -base64 24 > secrets/db_root_password.txt
	@test -f secrets/db_password.txt || openssl rand -base64 24 > secrets/db_password.txt
	@test -f secrets/wp_admin_password.txt || openssl rand -base64 24 > secrets/wp_admin_password.txt
	@test -f secrets/wp_user_password.txt || openssl rand -base64 24 > secrets/wp_user_password.txt
	@chmod 600 secrets/*.txt
	@echo "Secrets ready in ./secrets"

setup: secrets
	@mkdir -p $(DATA_PATH)/wordpress
	@mkdir -p $(DATA_PATH)/mariadb
	@mkdir -p $(DATA_PATH)/backup

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

.PHONY: all secrets setup build up down stop start logs ps clean fclean re
