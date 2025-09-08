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
Updates Terraform module source references to a new version using argparse.

This script recursively finds all '.tf' files in a given directory,
excluding '.terraform' folders, and updates the 'ref' version tag for
modules sourced from a specific GitHub path.
"""

import sys
import os
import re
import argparse

def main():
    """Handles command-line arguments and initiates the update process."""
    # --- Argument Parsing ---
    parser = argparse.ArgumentParser(
        description="Updates Terraform module source references to a new version.",
        formatter_class=argparse.RawTextHelpFormatter, # Allows for better formatting of the help message
        epilog="Example:\n  %(prog)s . v43.0.0"
    )
    parser.add_argument(
        "directory_path",
        metavar="<directory_path>",
        type=str,
        help="The target directory to search recursively for .tf files."
    )
    parser.add_argument(
        "new_version",
        metavar="<new_version>",
        type=str,
        help="The new version tag to set for the modules (e.g., 'v43.0.0')."
    )
    args = parser.parse_args()

    target_dir = args.directory_path
    new_version = args.new_version

    if not os.path.isdir(target_dir):
        print(f"Error: Directory not found at '{target_dir}'", file=sys.stderr)
        sys.exit(1)

    # --- Regex configuration ---
    prefix = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/"
    new_suffix = f"?ref={new_version}"

    pattern = re.compile(
        f'('                    # Start of capturing group 1
        f'"'                    # Literal opening quote
        f'{re.escape(prefix)}'  # The module path prefix
        f'[^"?\\s]*'            # The specific module name (e.g., 'iam')
        f')'                    # End of capturing group 1
        f'\\?ref=v[0-9\\.]*'    # The old version query string to be replaced
        f'"'                    # Literal closing quote
    )

    # --- Find .tf files, exclude .terraform, replace group 1 ---
    replacement = f'\\1{new_suffix}"'

    updated_files_count = 0

    for dirpath, dirnames, filenames in os.walk(target_dir):
        if '.terraform' in dirnames:
            dirnames.remove('.terraform')

        for filename in filenames:
            if filename.endswith(".tf"):
                file_path = os.path.join(dirpath, filename)
                try:
                    with open(file_path, 'r', encoding='utf-8') as file:
                        original_content = file.read()

                    updated_content = pattern.sub(replacement, original_content)

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
