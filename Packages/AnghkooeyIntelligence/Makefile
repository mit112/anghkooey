.PHONY: eval eval-update

# Run live eval against current model. Must be run from repo root.
# Requires macOS 26 with Apple Intelligence enabled.
eval:
	swift run --package-path Packages/AnghkooeyIntelligence EvalRunner

# Re-run live eval and overwrite golden fixtures with new model output.
# Commit the updated fixtures alongside any prompt template change.
eval-update:
	swift run --package-path Packages/AnghkooeyIntelligence EvalRunner --update-goldens
