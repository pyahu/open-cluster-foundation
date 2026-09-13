#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

MODULE_DIRECTORY_NAME="${1:-}"
OUTPUT_ROOT="${2:-}"

[[ "$MODULE_DIRECTORY_NAME" =~ ^[a-z0-9-]+$ ]] || die "module name must contain only lowercase letters, digits and hyphens"
[[ -n "$OUTPUT_ROOT" ]] || die "usage: scripts/package-terraform-module.sh <module-directory-name> <output-root>"

MODULE_DIRECTORY="${OCF_ROOT}/terraform/modules/${MODULE_DIRECTORY_NAME}"
MODULE_MANIFEST="${MODULE_DIRECTORY}/module.yaml"
require_file "$MODULE_MANIFEST"
require_command yq

REGISTRY_REPOSITORY="$(yq -er '.spec.registry.repository' "$MODULE_MANIFEST")"
[[ "$REGISTRY_REPOSITORY" =~ ^terraform-[a-z0-9-]+-[a-z0-9-]+$ ]] || die "invalid registry repository name: ${REGISTRY_REPOSITORY}"

mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"
PACKAGE_DIRECTORY="${OUTPUT_ROOT}/${REGISTRY_REPOSITORY}"
[[ ! -e "$PACKAGE_DIRECTORY" ]] || die "package destination already exists: ${PACKAGE_DIRECTORY}"
mkdir "$PACKAGE_DIRECTORY"

for source_file in "$MODULE_DIRECTORY"/*.tf "$MODULE_DIRECTORY"/README.md "$MODULE_DIRECTORY"/CHANGELOG.md "$MODULE_DIRECTORY"/VERSION "$MODULE_DIRECTORY"/module.yaml; do
  require_file "$source_file"
  cp "$source_file" "$PACKAGE_DIRECTORY/"
done

cp "${OCF_ROOT}/LICENSE" "$PACKAGE_DIRECTORY/LICENSE"
for directory_name in examples tests; do
  if [[ -d "${MODULE_DIRECTORY}/${directory_name}" ]]; then
    cp -R "${MODULE_DIRECTORY}/${directory_name}" "$PACKAGE_DIRECTORY/"
  fi
done

printf '%s\n' "$PACKAGE_DIRECTORY"
