.PHONY: help setup lint test run run-emulator clean

help:
	@echo "PawWatch Developer Commands:"
	@echo "  make setup          - Install Flutter dependencies"
	@echo "  make lint           - Run static analysis"
	@echo "  make test           - Run all unit and widget tests"
	@echo "  make run            - Run app in debug mode"
	@echo "  make run-emulator   - Run app connected to local Firebase emulators"
	@echo "  make emulators      - Start Firebase local emulator suite"
	@echo "  make clean          - Clean build cache and reinstall packages"

setup:
	flutter pub get

lint:
	flutter analyze

test:
	flutter test

run:
	flutter run

run-emulator:
	flutter run --dart-define=USE_EMULATOR=true

emulators:
	firebase emulators:start

clean:
	flutter clean
	flutter pub get
