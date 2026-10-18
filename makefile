.PHONY: help bootstrap package create-package layers format lint check-swift-access check-swift-file-groups check-conflict-review-ui check-package-resources build project open close preflight backend backend-reset backend-test %

help:
	@echo "make bootstrap"
	@echo "  Installs Mint tools, generates packages and the Xcode project"
	@echo "make package [NAME=PocketSync LAYER=Services]"
	@echo "  Creates a local package in Layers/<LAYER>, registers it, regenerates the project"
	@echo "make layers"
	@echo "  Validates layer dependencies and generates every Package.swift from imports"
	@echo "make format"
	@echo "  Formats all Swift code and runs SwiftLint"
	@echo "make check-swift-access"
	@echo "  Rejects redundant access modifiers inside extensions"
	@echo "make check-swift-file-groups"
	@echo "  Checks that split Swift types share a folder named after the type"
	@echo "make check-package-resources"
	@echo "  Checks packagebot resource bundle generation"
	@echo "make check-conflict-review-ui"
	@echo "  Checks shared conflict cards and adaptive glass actions"
	@echo "make build"
	@echo "  Builds for the iOS simulator with normal code signing"
	@echo "make project"
	@echo "  Regenerates PocketDemo.xcodeproj from project.yml"
	@echo "make open"
	@echo "  Opens the project in Xcode"
	@echo "make preflight"
	@echo "  Runs layers and format before committing"
	@echo "make backend | backend-reset | backend-test"
	@echo "  Runs, reseeds or tests the local Bun backend"
	@echo "make close"
	@echo "  Closes all Xcode instances"

bootstrap:
	@bash scripts/dev/bootstrap.sh

package:
	@bash scripts/dev/add_local_package.sh $(NAME) $(LAYER)
	@$(MAKE) layers
	@$(MAKE) project

create-package: package

layers:
	@ruby ./scripts/dev/packagebot/packagebot.rb

format:
	@bash scripts/dev/format.sh
	@echo "Formatting complete."

lint:
	@$(MAKE) check-swift-access
	@$(MAKE) check-swift-file-groups
	@$(MAKE) check-conflict-review-ui
	@mint run swiftlint --quiet

check-swift-access:
	@mint run swiftformat Layers PocketDemo --lint --rules redundantExtensionACL --cache ignore

check-swift-file-groups:
	@ruby scripts/dev/check_swift_file_groups.rb

check-conflict-review-ui:
	@ruby scripts/dev/check_conflict_review_ui.rb
	@ruby scripts/verification/VerifyConflictReviewUI.rb

check-package-resources:
	@ruby scripts/verification/VerifyPackageResources.rb

build:
	@xcodebuild -project PocketDemo.xcodeproj -scheme PocketDemo -destination 'generic/platform=iOS Simulator' build

project:
	@mint run xcodegen generate --spec project.yml

open:
	@$(MAKE) close
	@sleep 1
	@xed PocketDemo.xcodeproj

close:
	@killall Xcode 2>/dev/null || true

preflight:
	@$(MAKE) check-swift-file-groups
	@$(MAKE) check-conflict-review-ui
	@$(MAKE) layers
	@$(MAKE) format

backend:
	@cd backend && bun run start

backend-reset:
	@cd backend && bun run reset

backend-test:
	@cd backend && bun test

%:
	@echo "Error: Unknown target '$@'"
	@echo "Run 'make help' to see available targets"
	@exit 1
