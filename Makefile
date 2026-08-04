.PHONY: demo test

demo:
	@echo "GUI: swift run demo"
	@echo "CLI: swift run demo check hourclock"
	@echo "CLI: swift run demo interactive hourclock"

test:
	swift test --filter SwiftTLATests
