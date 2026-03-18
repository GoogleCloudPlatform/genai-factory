#!/usr/bin/env python3

# Copyright 2026 Google LLC
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


import subprocess
import sys
from unittest.mock import patch, MagicMock

import pytest

from tools import fetch_latest_tag


@pytest.fixture
def mock_sys_argv():
    with patch.object(sys, 'argv', ['fetch_latest_tag.py', 'http://example.com/repo.git']):
        yield


@patch('tools.fetch_latest_tag.tempfile.mkdtemp')
@patch('tools.fetch_latest_tag.shutil.rmtree')
@patch('tools.fetch_latest_tag.subprocess.run')
@patch('tools.fetch_latest_tag.subprocess.Popen')
def test_main_sort_by_version(mock_popen, mock_run, mock_rmtree, mock_mkdtemp, capsys, mock_sys_argv):
    # Mock temp directory
    mock_mkdtemp.return_value = '/tmp/testdir'

    # Mock git tag list process
    mock_git_list_proc = MagicMock()
    mock_git_list_proc.stdout.strip.return_value.splitlines.return_value = ['v1.0.0', 'v1.1.0', 'v2.0.0']

    # Mock sort process
    mock_sort_proc = MagicMock()
    mock_sort_proc.stdout.strip.return_value.splitlines.return_value = ['v1.0.0', 'v1.1.0', 'v2.0.0']

    # Mock latest tag process
    mock_latest_tag_proc = MagicMock()
    mock_latest_tag_proc.stdout.strip.return_value.splitlines.return_value = ['v2.0.0', 'v1.1.0', 'v1.0.0']

    mock_run.side_effect = [
        MagicMock(),  # git clone
        MagicMock(),  # git fetch
        mock_sort_proc,  # sort -V
        mock_latest_tag_proc  # git tag --list --sort=-v:refname
    ]
    mock_popen.return_value.stdout.read.return_value = "v1.0.0\nv2.0.0\nv1.1.0"
    mock_popen.return_value.stdout.close.return_value = None

    fetch_latest_tag.main()

    # Assert the latest tag is printed
    captured = capsys.readouterr()
    assert captured.out == 'v2.0.0\n'


@patch('tools.fetch_latest_tag.tempfile.mkdtemp')
@patch('tools.fetch_latest_tag.shutil.rmtree')
@patch('tools.fetch_latest_tag.subprocess.run')
@patch('tools.fetch_latest_tag.subprocess.Popen')
def test_main_sort_by_date(mock_popen, mock_run, mock_rmtree, mock_mkdtemp, capsys):
    # Mock command line arguments
    with patch.object(sys, 'argv', ['fetch_latest_tag.py', '--sort_by_date', 'http://example.com/repo.git']):
        # Mock temp directory
        mock_mkdtemp.return_value = '/tmp/testdir'

        # Mock git tag list process
        mock_git_list_proc = MagicMock()
        mock_git_list_proc.stdout.strip.return_value.splitlines.return_value = ['v1.0.0', 'v2.0.0', 'v1.1.0']

        # Mock sort process
        mock_sort_proc = MagicMock()
        mock_sort_proc.stdout.strip.return_value.splitlines.return_value = ['v1.0.0', 'v1.1.0', 'v2.0.0']

        # Mock latest tag process (date sorted)
        mock_latest_tag_proc_date = MagicMock()
        mock_latest_tag_proc_date.stdout.strip.return_value.splitlines.return_value = ['v1.1.0', 'v2.0.0', 'v1.0.0']

        mock_run.side_effect = [
            MagicMock(),  # git clone
            MagicMock(),  # git fetch
            mock_sort_proc,  # sort -V
            mock_latest_tag_proc_date,  # git tag --list 'v*' --sort=-committerdate
        ]
        mock_popen.return_value.stdout.read.return_value = "v1.0.0\nv2.0.0\nv1.1.0"
        mock_popen.return_value.stdout.close.return_value = None

        fetch_latest_tag.main()

        # Assert the latest tag is printed
        captured = capsys.readouterr()
        assert captured.out == 'v1.1.0\n'


@patch('tools.fetch_latest_tag.tempfile.mkdtemp')
@patch('tools.fetch_latest_tag.shutil.rmtree')
@patch('tools.fetch_latest_tag.subprocess.run', side_effect=subprocess.CalledProcessError(1, 'git', stderr=''))
def test_main_git_command_fails(mock_rmtree, mock_mkdtemp, capsys, mock_sys_argv):
    mock_mkdtemp.return_value = '/tmp/testdir'
    with pytest.raises(SystemExit) as cm:
        fetch_latest_tag.main()
    assert cm.value.code == 1
