# traflorkian-lab

Practice environment for EX370 Q8 ("Creating a Snapshot" — the `traflorkian` app).

This repo replaces the exam's unreachable `rhgls.domain11.example.com` materials with your own:
a throwaway GPG keypair, an encrypted page, and a small container image whose `ENTRYPOINT`
decrypts `/data/doc.gpg` to `/var/www/html/index.html` and serves it with `httpd -D FOREGROUND` —
same shape as the real exercise.

## What's in here
```
image/
  Containerfile     — builds the replica app image (non-root, UID 1000, home /home/appuser)
  entrypoint.sh      — decrypts /data/doc.gpg -> /var/www/html/index.html, then execs httpd
materials/
  doc.gpg                    — a page encrypted with a throwaway keypair (stands in for doc.gpg)
  private-keys-v1.d.tar      — the throwaway keypair, packaged like the real exercise's tar
```

The GPG key (`lab@example.com`) was generated only for this exercise and isn't tied to any
real identity — that's why it's safe to keep in a public repo. Don't reuse it for anything real.

## One-time setup

1. Create an **empty public repo** named `traflorkian-lab` at https://github.com/new under
   your account (sunilmohite). Don't initialize it with a README — this repo already has one.
2. From inside this folder:
   ```bash
   git init
   git add .
   git commit -m "traflorkian lab practice materials"
   git branch -M main
   git remote add origin https://github.com/sunilmohite/traflorkian-lab.git
   git push -u origin main
   ```
3. Confirm the materials are publicly fetchable:
   ```bash
   curl -sI https://raw.githubusercontent.com/sunilmohite/traflorkian-lab/main/materials/doc.gpg
   ```
   You should get `HTTP/2 200`.

## Deploying to your OpenShift cluster

Once you're logged in (`oc login ...`), run `deploy.sh` from this same folder — it runs every
`oc` command needed, in order, with your GitHub username already filled in. See that file for
what each step does; it mirrors the real Q8 procedure exactly from this point on.
