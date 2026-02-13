# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Usage: python update_copyright.py . 2026 [-e exclude_dir_1 exclude_dir_2]

import os
import re
import argparse
import sys


def is_binary(file_path):
    """
    Simple heuristic to detect binary files.
    Reads the first 1024 bytes and checks for null bytes.
    """
    try:
        with open(file_path, 'rb') as f:
            chunk = f.read(1024)
            return b'\0' in chunk
    except Exception:
        return True


def update_copyright_in_file(file_path, new_year, owner="Google LLC"):
    """
    Reads a file and updates the year in the copyright header.
    """
    # Regex: Matches "Copyright", the old 4-digit year, and the owner.
    pattern = re.compile(rf"(Copyright\s+)(\d{{4}})(\s+{re.escape(owner)})",
                         re.IGNORECASE)

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        if pattern.search(content):
            new_content = pattern.sub(rf"\g<1>{new_year}\g<3>", content)

            if content != new_content:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f"Updated: {file_path}")

    except (UnicodeDecodeError, PermissionError):
        # Silently skip files we can't read as text
        pass


def main():
    parser = argparse.ArgumentParser(
        description="Recursively update copyright years.")

    # Positional arguments
    parser.add_argument("root_path", help="The root folder to start searching")
    parser.add_argument("new_year", help="The new year (e.g., 2026)")

    # Optional argument for excludes
    parser.add_argument(
        "-e",
        "--exclude",
        nargs='*',
        default=[],
        help=
        "Space-separated list of folder names to ignore (e.g. .terraform build dist)"
    )

    args = parser.parse_args()

    if not os.path.isdir(args.root_path):
        print(f"Error: Directory '{args.root_path}' does not exist.")
        sys.exit(1)

    ignored_dirs = {
        '.git', '.terraform', '.idea', '.vscode', '__pycache__',
        'node_modules', 'venv', '.venv'
    }
    ignored_dirs.update(args.exclude)

    print(f"Scanning '{args.root_path}' (Copyright -> {args.new_year})...")
    print(f"Ignoring folders: {', '.join(sorted(ignored_dirs))}")

    for root, dirs, files in os.walk(args.root_path):
        # Modify 'dirs' in-place. This tells os.walk NOT to traverse these folders.
        # This is efficient because it prunes the tree preventing unrelated recursion.
        dirs[:] = [d for d in dirs if d not in ignored_dirs]

        for file in files:
            file_path = os.path.join(root, file)

            if is_binary(file_path):
                continue

            update_copyright_in_file(file_path, args.new_year)

    print("Done.")


if __name__ == "__main__":
    main()
