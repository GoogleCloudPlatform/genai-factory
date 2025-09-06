#!/usr/bin/env python3

# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Updates Terraform module source references to a new version.

This script recursively finds all '.tf' files in a given directory,
excluding '.terraform' folders, and updates the 'ref' version tag for
modules sourced from a specific GitHub path.
"""

import sys
import os
import re

def main():
    """Handles command-line arguments and initiates the update process."""
    # Check if the correct number of arguments are provided
    if len(sys.argv) != 3:
        script_name = os.path.basename(sys.argv[0])
        print("Error: Please provide the target directory and the new version.", file=sys.stderr)
        print(f"Usage: {script_name} <directory_path> <new_version>", file=sys.stderr)
        print(f"Example: {script_name} . v43.0.0", file=sys.stderr)
        sys.exit(1)

    target_dir = sys.argv[1]
    new_version = sys.argv[2]

    # Verify that the target directory exists
    if not os.path.isdir(target_dir):
        print(f"Error: Directory not found at '{target_dir}'", file=sys.stderr)
        sys.exit(1)

    # --- Configuration ---
    prefix = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/"
    new_suffix = f"?ref={new_version}"

    # Regex to find module sources with the specified prefix and an old version tag.
    # It captures the part of the string before the version query parameter.
    # Example match for: "github.com/.../modules/iam?ref=v26.0.0"
    # Capturing Group 1 will contain: "github.com/.../modules/iam
    pattern = re.compile(
        f'('                          # Start of capturing group 1
        f'"'                          # Literal opening quote
        f'{re.escape(prefix)}'        # The module path prefix
        f'[^"?\\s]*'                  # The specific module name (e.g., 'iam')
        f')'                          # End of capturing group 1
        f'\\?ref=v[0-9\\.]*'          # The old version query string to be replaced
        f'"'                          # Literal closing quote
    )

    # The replacement string uses a backreference (\1) to the captured group,
    # followed by the new version suffix and a closing quote.
    replacement = f'\\1{new_suffix}"'

    updated_files_count = 0

    # Recursively walk through the directory tree
    for dirpath, dirnames, filenames in os.walk(target_dir):
        # Prune the .terraform directory from the search to avoid descending into it
        if '.terraform' in dirnames:
            dirnames.remove('.terraform')

        for filename in filenames:
            if filename.endswith(".tf"):
                file_path = os.path.join(dirpath, filename)
                try:
                    # Read the original file content
                    with open(file_path, 'r', encoding='utf-8') as file:
                        original_content = file.read()

                    # Perform the substitution using the compiled regex
                    updated_content = pattern.sub(replacement, original_content)

                    # Write back to the file only if changes were made
                    if original_content != updated_content:
                        with open(file_path, 'w', encoding='utf-8') as file:
                            file.write(updated_content)
                        print(f"Updated: {file_path}")
                        updated_files_count += 1

                except (IOError, OSError) as e:
                    print(f"Error processing file {file_path}: {e}", file=sys.stderr)

    print(f"\nDone. Updated {updated_files_count} file(s).")

if __name__ == "__main__":
    main()
