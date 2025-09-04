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
Clones a Git repository into a temporary directory to find and display
the most recent version tag (prefixed with 'v').
"""

import sys
import subprocess
import tempfile
import shutil
import os

def main():
    """Main function to execute the script's logic."""
    # --- Check if a repository URL is provided ---
    if len(sys.argv) != 2:
        script_name = os.path.basename(sys.argv[0])
        print(f"Usage: {script_name} <repository_url>", file=sys.stderr)
        print(f"Example: {script_name} https://github.com/git/git.git", file=sys.stderr)
        sys.exit(1)

    repo_url = sys.argv[1]

    # --- Create a temporary directory ---
    # The 'temp_dir' will be automatically cleaned up in the 'finally' block.
    temp_dir = tempfile.mkdtemp()

    try:
        print(f"🔍 Cloning repository and fetching tags from: {repo_url}")

        # --- Clone the repository without checking out files ---
        # The subprocess runs git commands safely and portably.
        subprocess.run(
            ['git', 'clone', '--quiet', '--no-checkout', '--depth', '1', repo_url, temp_dir],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

        # --- Fetch all tags from the remote repository ---
        subprocess.run(
            ['git', 'fetch', '--quiet', '--tags'],
            cwd=temp_dir, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

        # --- Get all tags starting with 'v', sorted by version number (for display) ---
        # For older Git versions, we can't use '--sort=V'. Instead, we pipe the
        # output from 'git tag' to the system's 'sort -V' command.
        git_list_proc = subprocess.Popen(
            ['git', 'tag', '--list', 'v*'],
            cwd=temp_dir, stdout=subprocess.PIPE
        )
        sort_proc = subprocess.run(
            ['sort', '-V'],
            stdin=git_list_proc.stdout, capture_output=True, text=True, check=True
        )
        # Allow git_list_proc to receive a SIGPIPE if sort_proc exits.
        git_list_proc.stdout.close()

        # Split the string output from the 'sort' command into a list of tags
        all_v_tags = sort_proc.stdout.strip().splitlines()

        # --- Get the latest tag based on the commit date ---
        latest_tag_proc = subprocess.run(
            ['git', 'tag', '--list', 'v*', '--sort=-committerdate'],
            cwd=temp_dir, capture_output=True, text=True, check=True
        )
        date_sorted_tags = latest_tag_proc.stdout.strip().splitlines()
        # The latest tag is the first one in the date-sorted list
        latest_tag_by_date = date_sorted_tags[0] if date_sorted_tags else ""

        print("---")

        # --- Display all 'v' tags for context ---
        print("📝 All tags in the repository starting with 'v':")
        if all_v_tags:
            print('\n'.join(all_v_tags))
        else:
            print("(No tags starting with 'v' found)")

        print("---")

        # --- Print the final result ---
        print(latest_tag_by_date)

    except subprocess.CalledProcessError as e:
        print(f"\nError: A git command failed with exit code {e.returncode}.", file=sys.stderr)
        print(f"--- Git's Error Message (stderr) ---", file=sys.stderr)
        print(e.stderr, file=sys.stderr)
        print(f"------------------------------------", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\nAn unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # --- Clean up the temporary directory ---
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
            print("---")
            print(f"🗑️ Cleaned up temporary directory: {temp_dir}")


if __name__ == "__main__":
    main()
