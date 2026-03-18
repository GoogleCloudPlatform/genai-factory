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

from typing import Optional
import re

PROACTIVE_WELCOME_EVENT = "PROACTIVE_WELCOME_EVENT"


def before_agent_callback(
        callback_context: CallbackContext) -> Optional[Content]:
    """
  This callback executes *before* the agent begins its main processing logic.
  """
    last_user_message = None

    if callback_context.user_content and callback_context.user_content.parts:
        last_user_message = callback_context.user_content.parts[0].text

    if not last_user_message or not isinstance(last_user_message, str):
        print("No user message found")
        return

    # Event Handling

    event_match = re.search(r"<event>(.*?)</event>", last_user_message)
    event_type = event_match.group(1) if event_match else None

    if event_type == PROACTIVE_WELCOME_EVENT:
        print("Proactive welcome event detected")
        callback_context.state[
            "internal__event_type"] = PROACTIVE_WELCOME_EVENT
        return
