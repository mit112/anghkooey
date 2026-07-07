.PHONY: generate

generate:
	xcodegen generate --spec App/project.yml --project App
	python3 scripts/patch_privacy_info.py
