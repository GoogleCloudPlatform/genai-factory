from typing import Optional
import re

PROACTIVE_WELCOME_EVENT = "PROACTIVE_WELCOME_EVENT"

def before_agent_callback(callback_context: CallbackContext) -> Optional[Content]:
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
    callback_context.state["internal__event_type"] = PROACTIVE_WELCOME_EVENT
    return
