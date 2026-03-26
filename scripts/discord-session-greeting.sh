#!/usr/bin/env bash
# Session greeting is now handled by the patched server.ts (client 'ready' event).
# The server only runs when --channels is active, so greetings are correctly scoped.
# This script is kept as a no-op for backward compatibility with existing hook registrations.
exit 0
