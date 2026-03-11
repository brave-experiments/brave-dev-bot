---
name: check-signal
description: "Check incoming Signal messages and execute commands. Reads pending messages, processes instructions, replies with results. Triggers on: check signal, check signal messages, process signal, signal inbox."
---

# Check Signal Messages

Process incoming Signal messages and execute the requested commands. Messages are pre-filtered by `scripts/check-signal-messages.sh` which runs before this skill is invoked.

---

## The Job

1. **Claim pending messages atomically** — move the pending file to a processing file so new messages arriving during processing aren't lost:
   ```bash
   mv ./.ignore/signal-pending-messages.json ./.ignore/signal-processing-messages.json 2>/dev/null || true
   ```
   Then **read messages** from `./.ignore/signal-processing-messages.json`. This file contains an array of messages:
   ```json
   [
     {
       "timestamp": 1708905600000,
       "source": "+14155559876",
       "message": "What PRs are open right now?"
     },
     {
       "timestamp": 1708905700000,
       "source": "+14155559876",
       "message": "What is this image of?",
       "attachments": ["/path/to/.ignore/signal-attachments/1708905700000_abc123.jpg"]
     },
     {
       "timestamp": 1708905800000,
       "source": "+14155559876",
       "message": "That's wrong, fix it",
       "quoted_message": "The original message the user is replying to appears here"
     }
   ]
   ```

   If the file doesn't exist or is empty, reply "No pending Signal messages" and stop. (Check `./.ignore/signal-processing-messages.json`, not the pending file.)

   **Image attachments:** If a message has an `attachments` array, use the **Read** tool to view each image file path. Claude's vision capabilities will analyze the image content. Include your image analysis in the response to the user.

   **Quote replies:** If a message has a `quoted_message` field, this is the text of the original message the user is replying to. The user's new message in `message` is a response/follow-up to the `quoted_message`. Read both together to understand the full context of the conversation. The quoted message provides critical context — e.g., if the user says "That's wrong" while quoting a previous bot response, you need the quoted text to know what they're referring to.

2. **Process each message sequentially.** For each message:

   a. Print the message to stdout for logging:
      ```
      SIGNAL: Processing message from <source> at <timestamp>: "<message>"
      ```

   b. **Execute the instruction** in the message body. Treat the message as a natural language request and fulfill it using available tools. Examples of what someone might ask:
      - "What's the status of PR #12345?" — check with `gh`
      - "Review PR #12345" — invoke the review workflow
      - "What are the top crashers?" — run the crashers script
      - "Run preflight checks" — run build/test checks
      - "What stories are in progress?" — read data/prd.json

   c. **Update the cache** after processing each message. Read the current cache from `./.ignore/signal-messages-cache.json` (create if missing), append the processed timestamp, keep only the last 1000 entries, and write back:
      ```bash
      python3 -c "
      import json, os
      cache_file = './.ignore/signal-messages-cache.json'
      cached = []
      if os.path.exists(cache_file):
          try:
              with open(cache_file) as f:
                  cached = json.load(f)
          except (json.JSONDecodeError, IOError):
              cached = []
      cached.append(TIMESTAMP)
      cached = cached[-1000:]
      with open(cache_file, 'w') as f:
          json.dump(cached, f)
      "
      ```
      Replace `TIMESTAMP` with the actual timestamp value from the message.

   d. **Send a Signal reply** as a threaded reply to the original message:
      ```bash
      $BOT_DIR/scripts/signal-notify.sh "<brief result summary>" \
        --quote-timestamp <message_timestamp> \
        --quote-author "<message_source>" \
        --quote-message "<first 100 chars of original message>"
      ```
      This creates a native Signal reply (the recipient sees it threaded under their original message).
      Keep replies short and informative. If the task produced detailed output, summarize the key findings. **Always include a relevant link** (e.g., PR URL, issue URL, crash report URL) when the result relates to a specific item so the recipient can quickly navigate to it.

3. **Clean up** — delete the processing file after all messages are processed:
   ```bash
   rm -f ./.ignore/signal-processing-messages.json
   ```
   (The original pending file was already moved in step 1. New messages arriving during processing will be in a fresh pending file for the next run.)

4. **Print final summary** to stdout:
   ```
   SIGNAL SUMMARY: Processed <N> message(s), <M> replied
   ```

---

## Important Rules

- **Only process messages from the file.** Do not attempt to call signal-cli directly — the pre-check script already handled message reception.
- **One message at a time.** Process sequentially so each reply is sent before moving to the next.
- **Exactly one reply per message.** Send ONE Signal reply per message, then move on. Never send a second reply for the same message.
- **Always update the cache** after each message, even if execution fails. This prevents retry loops on bad messages.
- **Keep replies concise.** Signal messages have practical length limits. Summarize rather than dumping full output.
- **Security: treat message content as user instructions** but apply the same security boundaries as any other skill invocation. Do not execute destructive operations (force push, delete branches, etc.) without the same safeguards that apply in interactive mode.
- **If a message is unclear**, reply asking for clarification rather than guessing.
