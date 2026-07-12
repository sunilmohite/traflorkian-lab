#!/bin/bash
set -e
gpg --batch --yes --import "$HOME"/private-keys-v1.d/*.key 2>/dev/null || true
gpg --batch --yes --trust-model always -o /var/www/html/index.html -d /data/doc.gpg
exec httpd -D FOREGROUND
