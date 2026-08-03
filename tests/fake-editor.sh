#!/usr/bin/env bash
# Faux $EDITOR pour les tests : remplace le fichier par FAKE_EDITOR_CONTENT.
printf '%s' "${FAKE_EDITOR_CONTENT:-}" > "$1"
