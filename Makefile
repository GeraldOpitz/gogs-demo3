APP_NAME=gogs
APP_DIR=/opt/gogs

setup: build run

build:
	@echo "Building Gogs..."
	go build -o $(APP_NAME)

run:
	@echo "Launching Gogs..."
	./$(APP_NAME) web
