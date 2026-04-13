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

import functions_framework
from flask import jsonify


@functions_framework.http
def main(request):
  """HTTP Cloud Function for Dialogflow CX Webhook fulfillment.
    
    Args:
        request (flask.Request): The incoming HTTP request object from Dialogflow.
        
    Returns:
        A JSON response formatted specifically for Dialogflow CX fulfillment,
        along with an HTTP 200 status code.
    """

  # Parse the incoming JSON request from Dialogflow
  req = request.get_json(silent=True)

  # Log the incoming request to the Cloud Console for debugging purposes
  print(f"Received request: {req}")

  # Construct the fulfillment response
  res = {
      "fulfillment_response": {
          "messages": [{
              "text": {
                  "text": [
                      'Hello! Just letting you know this message was generated from the webhook code.'
                  ]
              }
          }]
      }
  }

  # Return the dictionary as a JSON response with a 200 OK status
  return jsonify(res), 200
